import 'package:ag_ui/ag_ui.dart';
import 'package:soliplex_client/src/application/json_patch.dart';
import 'package:soliplex_client/src/domain/activity_record.dart';
import 'package:soliplex_client/src/domain/skill_tool_call_activity.dart'
    show kSkillToolCallActivityType, kSkillToolResultActivityType;
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _defaultLogger =
    LogManager.instance.getLogger('soliplex_client.activity_events');

/// Applies one AG-UI activity event to [current], returning the new
/// activity list per AG-UI semantics:
///
/// - [ActivitySnapshotEvent] with `replace=true` overwrites a record at
///   the matching `messageId`; with `replace=false` it is ignored when
///   a record at that id already exists. A snapshot without a prior
///   entry is appended.
/// - [ActivityDeltaEvent] applies its RFC 6902 patch to the matching
///   record's `content`. Drops the patch with an error log when no
///   prior snapshot exists or when the delta's `activityType` does not
///   match the existing record.
/// - Any other event is returned unchanged.
///
/// Missing timestamps fall back to `DateTime.now().millisecondsSinceEpoch`
/// so historical replay produces stable timestamps even when the
/// backend omits them.
List<ActivityRecord> applyActivityEvent(
  List<ActivityRecord> current,
  BaseEvent event, {
  Logger? logger,
}) {
  final log = logger ?? _defaultLogger;
  return switch (event) {
    ActivitySnapshotEvent() => _applySnapshot(current, event, log),
    ActivityDeltaEvent() => _applyDelta(current, event, log),
    _ => current,
  };
}

List<ActivityRecord> _applySnapshot(
  List<ActivityRecord> current,
  ActivitySnapshotEvent event,
  Logger log,
) {
  // `content` is `Object?` upstream, but `ActivityRecord.content` is a
  // `Map<String, dynamic>`. This fold stays non-throwing, so it warns and
  // leaves the list untouched. A caller that needs a non-object payload
  // surfaced to the user checks `content` before folding.
  final eventContent = event.content;
  if (eventContent is! Map<String, dynamic>) {
    log.warning(
      'ActivitySnapshotEvent dropped: content is '
      '${eventContent.runtimeType}, not a Map<String, dynamic> '
      '(messageId: ${event.messageId}, activityType: ${event.activityType})',
      attributes: {
        'messageId': event.messageId,
        'activityType': event.activityType,
        'contentType': eventContent.runtimeType.toString(),
      },
    );
    return current;
  }
  final resolvedTimestamp =
      event.timestamp ?? DateTime.now().millisecondsSinceEpoch;
  final idx = current.indexWhere((a) => a.messageId == event.messageId);
  if (idx >= 0) {
    if (!event.replace) return current;
    final content = _mergeContentAcrossReplace(
      current[idx],
      event.activityType,
      eventContent,
    );
    return [...current]..[idx] = ActivityRecord(
        messageId: event.messageId,
        activityType: event.activityType,
        content: content,
        timestamp: resolvedTimestamp,
      );
  }
  return [
    ...current,
    ActivityRecord(
      messageId: event.messageId,
      activityType: event.activityType,
      content: eventContent,
      timestamp: resolvedTimestamp,
    ),
  ];
}

/// Carries the call phase's `args` onto a `skill_tool_result` snapshot
/// that replaces it in place. Preserves the unified-row UI contract
/// across AG-UI's call→result replace boundary: the result phase does
/// not transmit `args`, but the same logical row continues to display
/// the inputs that produced the result.
Map<String, dynamic> _mergeContentAcrossReplace(
  ActivityRecord prior,
  String activityType,
  Map<String, dynamic> content,
) {
  if (activityType != kSkillToolResultActivityType) return content;
  if (prior.activityType != kSkillToolCallActivityType) return content;
  if (content.containsKey('args')) return content;
  final priorArgs = prior.content['args'];
  if (priorArgs == null) return content;
  return {...content, 'args': priorArgs};
}

// AG-UI protocol violations on the delta path (missing prior snapshot,
// activityType mismatch) are dropped silently from the UI's perspective:
// the existing record stays at its prior state, no drop tile is minted.
// This is intentionally asymmetric with `_processStateSnapshot`, which
// throws on bad input and lets the orchestrator append a visible
// `DroppedEventMessage`. The unified activity row remains usable across
// a dropped delta (the row simply doesn't advance), so a drop tile
// would be visual noise. The error-level log is the backend-escalation
// channel; UI consumers see no change.
List<ActivityRecord> _applyDelta(
  List<ActivityRecord> current,
  ActivityDeltaEvent event,
  Logger log,
) {
  final idx = current.indexWhere((a) => a.messageId == event.messageId);
  if (idx < 0) {
    log.error(
      'ActivityDeltaEvent dropped: no prior snapshot for messageId '
      '(AG-UI protocol violation)',
      attributes: {
        'messageId': event.messageId,
        'activityType': event.activityType,
        'patchOps': event.patch.length,
      },
    );
    return current;
  }
  final existing = current[idx];
  if (existing.activityType != event.activityType) {
    log.error(
      'ActivityDeltaEvent dropped: activityType mismatch',
      attributes: {
        'messageId': event.messageId,
        'expected': existing.activityType,
        'received': event.activityType,
        'patchOps': event.patch.length,
      },
    );
    return current;
  }
  final patched = applyJsonPatch(existing.content, event.patch, logger: log);
  return [...current]..[idx] = ActivityRecord(
      messageId: event.messageId,
      activityType: event.activityType,
      content: patched,
      timestamp: event.timestamp ?? existing.timestamp,
    );
}
