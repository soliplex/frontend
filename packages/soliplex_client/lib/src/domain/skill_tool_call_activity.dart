import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'package:soliplex_client/src/domain/activity_record.dart';
import 'package:soliplex_client/src/domain/conversation.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex_client.skill_tool_call_activity');

/// Lifecycle status of a [SkillToolCallActivity].
///
/// Decoded from `content['status']` when the backend supplies a value;
/// otherwise synthesized from the activityType
/// (`skill_tool_call → inProgress`, `skill_tool_result → done`).
/// [parse] coalesces alternate string spellings the backend may emit.
enum SkillToolCallStatus {
  /// Tool invocation in flight; result not yet available.
  inProgress('in_progress'),

  /// Tool invocation completed successfully.
  done('done'),

  /// Tool invocation failed.
  error('error'),

  /// Status was unrecognised — preserved so the renderer can fall back.
  unknown('unknown');

  const SkillToolCallStatus(this.label);

  /// Canonical lowercase label for telemetry and UI display.
  final String label;

  /// Coalesces a backend status token onto the canonical set. Returns
  /// [unknown] when [raw] is `null` or not one of the recognised
  /// spellings.
  static SkillToolCallStatus parse(String? raw) {
    switch (raw) {
      case 'in_progress':
      case 'running':
        return SkillToolCallStatus.inProgress;
      case 'done':
      case 'completed':
      case 'success':
        return SkillToolCallStatus.done;
      case 'failed':
      case 'error':
        return SkillToolCallStatus.error;
      case null:
      default:
        return SkillToolCallStatus.unknown;
    }
  }
}

/// Typed view of a `skill_tool_call` or `skill_tool_result` activity
/// record.
///
/// One logical tool invocation arrives as two snapshots sharing a
/// `messageId`: the call phase (`activity_type='skill_tool_call'`,
/// carrying `args`) and the result phase (`activity_type=
/// 'skill_tool_result'`, carrying `result`, with `replace=true`). This
/// view decodes either phase so the timeline row can render
/// continuously across the transition.
///
/// [status] is sourced from `content['status']` when explicitly
/// provided as a `String`; otherwise it is synthesized from the
/// activityType (`skill_tool_call → inProgress`, `skill_tool_result
/// → done`) so the renderer can switch exhaustively on the enum.
///
/// Construct via [SkillToolCallActivity.fromRecord], which returns
/// `null` when the record is not a well-formed skill tool activity.
/// The underlying [ActivityRecord] stays authoritative — this is a
/// read view for UI consumers, not a replacement.
@immutable
class SkillToolCallActivity {
  /// Creates a [SkillToolCallActivity]. Prefer [fromRecord].
  const SkillToolCallActivity({
    required this.messageId,
    required this.toolName,
    required this.args,
    required this.result,
    required this.status,
    required this.timestamp,
  });

  /// Attempts to decode [record] as a [SkillToolCallActivity].
  ///
  /// Dispatches on [ActivityRecord.activityType]:
  /// - `skill_tool_call` → decodes args, synthesizes status
  ///   `'in_progress'` when [ActivityRecord.content] does not carry
  ///   an explicit `status` String.
  /// - `skill_tool_result` → decodes the optional `result` String,
  ///   synthesizes status `'done'` when no explicit `status` is set.
  /// - any other activityType → returns `null`.
  ///
  /// Both phases require `content['tool_name']` to be a `String`.
  /// Schema drift is logged (level 900) rather than thrown, matching
  /// the processor's posture in `_processActivitySnapshot`.
  static SkillToolCallActivity? fromRecord(ActivityRecord record) {
    switch (record.activityType) {
      case 'skill_tool_call':
        return _decodeCall(record);
      case 'skill_tool_result':
        return _decodeResult(record);
      default:
        return null;
    }
  }

  static SkillToolCallActivity? _decodeCall(ActivityRecord record) {
    final toolName = _readToolName(record);
    if (toolName == null) return null;

    final args = _decodeArgs(record);
    if (args == null) return null;

    return SkillToolCallActivity(
      messageId: record.messageId,
      toolName: toolName,
      args: args,
      result: null,
      status: _decodeStatus(record, fallback: SkillToolCallStatus.inProgress),
      timestamp: record.timestamp,
    );
  }

  static SkillToolCallActivity? _decodeResult(ActivityRecord record) {
    final toolName = _readToolName(record);
    if (toolName == null) return null;

    final rawResult = record.content['result'];
    final String? result;
    if (rawResult == null || rawResult is String) {
      result = rawResult as String?;
    } else {
      _logger.warning(
        'SkillToolCallActivity: skill_tool_result `result` field has '
        'unexpected type; coerced to null',
        attributes: {
          'messageId': record.messageId,
          'resultType': rawResult.runtimeType.toString(),
        },
      );
      result = null;
    }

    return SkillToolCallActivity(
      messageId: record.messageId,
      toolName: toolName,
      args: const {},
      result: result,
      status: _decodeStatus(record, fallback: SkillToolCallStatus.done),
      timestamp: record.timestamp,
    );
  }

  static String? _readToolName(ActivityRecord record) {
    final toolName = record.content['tool_name'];
    if (toolName is String) return toolName;
    _logger.warning(
      'SkillToolCallActivity.fromRecord: missing or invalid tool_name',
      attributes: {
        'messageId': record.messageId,
        'toolNameType': toolName.runtimeType.toString(),
      },
    );
    return null;
  }

  /// Returns `null` when the args field is structurally invalid (the
  /// decoder should abandon the record). Returns an empty map when
  /// args are simply absent.
  static Map<String, dynamic>? _decodeArgs(ActivityRecord record) {
    final rawArgs = record.content['args'];
    switch (rawArgs) {
      case null:
        return const {};
      case final String s when s.isEmpty:
        return const {};
      case final String s:
        return _tryDecodeJsonObject(s, record.messageId);
      case final Map<String, dynamic> m:
        return m;
      default:
        _logger.warning(
          'SkillToolCallActivity.fromRecord: unexpected args runtimeType',
          attributes: {
            'messageId': record.messageId,
            'argsType': rawArgs.runtimeType.toString(),
          },
        );
        return null;
    }
  }

  static SkillToolCallStatus _decodeStatus(
    ActivityRecord record, {
    required SkillToolCallStatus fallback,
  }) {
    final raw = record.content['status'];
    if (raw is! String) return fallback;
    return SkillToolCallStatus.parse(raw);
  }

  /// Identifier for the target `ActivityMessage`.
  final String messageId;

  /// Tool being invoked (e.g. `"ask"`).
  final String toolName;

  /// Decoded arguments for the tool call. Empty when the record is a
  /// `skill_tool_result` (the result snapshot does not carry args per
  /// the AG-UI replace-in-place contract) or when args are absent.
  final Map<String, dynamic> args;

  /// Decoded result from a `skill_tool_result` record. `null` while the
  /// record is still a `skill_tool_call`, or when the result snapshot
  /// did not include a `result` field.
  final String? result;

  /// Lifecycle status. Synthesized from the activityType when
  /// `content['status']` is absent or unparseable; otherwise reflects
  /// the backend's value parsed through [SkillToolCallStatus.parse].
  final SkillToolCallStatus status;

  /// Event timestamp for the underlying snapshot.
  final int timestamp;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SkillToolCallActivity) return false;
    const mapEquals = DeepCollectionEquality();
    return messageId == other.messageId &&
        toolName == other.toolName &&
        result == other.result &&
        status == other.status &&
        timestamp == other.timestamp &&
        mapEquals.equals(args, other.args);
  }

  @override
  int get hashCode => Object.hash(
        messageId,
        toolName,
        result,
        status,
        timestamp,
        const DeepCollectionEquality().hash(args),
      );

  @override
  String toString() => 'SkillToolCallActivity(messageId: $messageId, '
      'toolName: $toolName, status: $status, timestamp: $timestamp)';
}

Map<String, dynamic>? _tryDecodeJsonObject(String raw, String messageId) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    _logger.warning(
      'SkillToolCallActivity.fromRecord: args decoded to non-object JSON',
      attributes: {
        'messageId': messageId,
        'decodedType': decoded.runtimeType.toString(),
      },
    );
    return null;
  } on FormatException catch (e) {
    _logger.warning(
      'SkillToolCallActivity.fromRecord: args JSON parse failed',
      attributes: {'messageId': messageId, 'error': e.toString()},
    );
    return null;
  }
}

/// Typed accessors for [Conversation.activities].
extension ConversationSkillToolCalls on Conversation {
  /// All skill tool activities in [activities], decoded to the typed
  /// view. Malformed records are skipped (see
  /// [SkillToolCallActivity.fromRecord]).
  List<SkillToolCallActivity> get skillToolCalls => [
        for (final record in activities)
          if (SkillToolCallActivity.fromRecord(record) case final call?) call,
      ];
}
