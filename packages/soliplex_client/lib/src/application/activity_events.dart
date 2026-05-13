import 'package:ag_ui/ag_ui.dart';
import 'package:soliplex_client/src/application/json_patch.dart';
import 'package:soliplex_client/src/domain/activity_record.dart';
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
    ActivitySnapshotEvent() => _applySnapshot(current, event),
    ActivityDeltaEvent() => _applyDelta(current, event, log),
    _ => current,
  };
}

List<ActivityRecord> _applySnapshot(
  List<ActivityRecord> current,
  ActivitySnapshotEvent event,
) {
  final resolvedTimestamp =
      event.timestamp ?? DateTime.now().millisecondsSinceEpoch;
  final idx = current.indexWhere((a) => a.messageId == event.messageId);
  if (idx >= 0) {
    if (!event.replace) return current;
    final content = _mergeContentAcrossReplace(current[idx], event);
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
      content: event.content,
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
  ActivitySnapshotEvent event,
) {
  if (event.activityType != 'skill_tool_result') return event.content;
  if (prior.activityType != 'skill_tool_call') return event.content;
  if (event.content.containsKey('args')) return event.content;
  final priorArgs = prior.content['args'];
  if (priorArgs == null) return event.content;
  return {...event.content, 'args': priorArgs};
}

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
