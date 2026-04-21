import 'dart:convert';
import 'dart:developer' as developer;

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'package:soliplex_client/src/domain/activity_record.dart';
import 'package:soliplex_client/src/domain/conversation.dart';

/// Typed view of a `skill_tool_call` activity record.
///
/// Decodes the raw [ActivityRecord.content] bag for the
/// `skill_tool_call` [ActivityRecord.activityType]. The `args` field in
/// the raw content is a double-encoded JSON string per the backend
/// contract; this class decodes it into a plain map.
///
/// Construct via [SkillToolCallActivity.fromRecord], which returns
/// `null` when the record is not a well-formed skill_tool_call. The
/// underlying [ActivityRecord] stays authoritative — this is a read
/// view for UI consumers, not a replacement.
@immutable
class SkillToolCallActivity {
  /// Creates a [SkillToolCallActivity]. Prefer [fromRecord].
  const SkillToolCallActivity({
    required this.messageId,
    required this.toolName,
    required this.args,
    required this.status,
    required this.timestamp,
  });

  /// Attempts to decode [record] as a [SkillToolCallActivity].
  ///
  /// Returns `null` when:
  /// - [ActivityRecord.activityType] is not `"skill_tool_call"`
  /// - `content['tool_name']` is missing or not a [String]
  /// - `content['args']` is present but not decodable as a JSON object
  ///
  /// Missing `args` yields an empty map; missing `status` yields `null`.
  /// Schema drift is logged (warning) rather than thrown, matching the
  /// processor's posture in `_processActivitySnapshot`.
  static SkillToolCallActivity? fromRecord(ActivityRecord record) {
    if (record.activityType != 'skill_tool_call') {
      return null;
    }
    final toolName = record.content['tool_name'];
    if (toolName is! String) {
      developer.log(
        'SkillToolCallActivity.fromRecord: missing or invalid tool_name '
        '(runtimeType=${toolName.runtimeType}) for messageId '
        '${record.messageId}',
        name: 'soliplex_client.skill_tool_call_activity',
        level: 900,
      );
      return null;
    }

    final rawArgs = record.content['args'];
    final Map<String, dynamic> decodedArgs;
    switch (rawArgs) {
      case null:
        decodedArgs = const {};
      case final String s when s.isEmpty:
        decodedArgs = const {};
      case final String s:
        final parsed = _tryDecodeJsonObject(s, record.messageId);
        if (parsed == null) {
          return null;
        }
        decodedArgs = parsed;
      case final Map<String, dynamic> m:
        decodedArgs = m;
      default:
        developer.log(
          'SkillToolCallActivity.fromRecord: unexpected args '
          'runtimeType=${rawArgs.runtimeType} for messageId '
          '${record.messageId}',
          name: 'soliplex_client.skill_tool_call_activity',
          level: 900,
        );
        return null;
    }

    final rawStatus = record.content['status'];
    final status = rawStatus is String ? rawStatus : null;

    return SkillToolCallActivity(
      messageId: record.messageId,
      toolName: toolName,
      args: decodedArgs,
      status: status,
      timestamp: record.timestamp,
    );
  }

  /// Identifier for the target `ActivityMessage`.
  final String messageId;

  /// Tool being invoked (e.g. `"ask"`).
  final String toolName;

  /// Decoded arguments for the tool call. Empty when absent.
  final Map<String, dynamic> args;

  /// Optional status token (e.g. `"in_progress"`, `"done"`).
  final String? status;

  /// Event timestamp for the underlying snapshot.
  final int timestamp;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SkillToolCallActivity) return false;
    const mapEquals = DeepCollectionEquality();
    return messageId == other.messageId &&
        toolName == other.toolName &&
        status == other.status &&
        timestamp == other.timestamp &&
        mapEquals.equals(args, other.args);
  }

  @override
  int get hashCode => Object.hash(
    messageId,
    toolName,
    status,
    timestamp,
    const DeepCollectionEquality().hash(args),
  );

  @override
  String toString() =>
      'SkillToolCallActivity(messageId: $messageId, '
      'toolName: $toolName, status: $status, timestamp: $timestamp)';
}

Map<String, dynamic>? _tryDecodeJsonObject(String raw, String messageId) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    developer.log(
      'SkillToolCallActivity.fromRecord: args decoded to '
      '${decoded.runtimeType}, not a JSON object, for messageId '
      '$messageId',
      name: 'soliplex_client.skill_tool_call_activity',
      level: 900,
    );
    return null;
  } on FormatException catch (e) {
    developer.log(
      'SkillToolCallActivity.fromRecord: args JSON parse failed for '
      'messageId $messageId: $e',
      name: 'soliplex_client.skill_tool_call_activity',
      level: 900,
    );
    return null;
  }
}

/// Typed accessors for [Conversation.activities].
extension ConversationSkillToolCalls on Conversation {
  /// All `skill_tool_call` activities in [activities], decoded to the
  /// typed view. Malformed records are skipped (see
  /// [SkillToolCallActivity.fromRecord]).
  List<SkillToolCallActivity> get skillToolCalls => [
    for (final record in activities)
      if (SkillToolCallActivity.fromRecord(record) case final call?) call,
  ];
}
