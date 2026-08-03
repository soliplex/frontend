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
    if (!event.replace) {
      // AG-UI's upsert semantic: the record stands and this payload is
      // discarded. Logged because it is the only drop on this path with
      // nothing else to show it happened — no tile, no state change, and a
      // row that keeps rendering content the producer meant to supersede.
      log.warning(
        'ActivitySnapshotEvent discarded: replace is false and a record '
        'already exists at this messageId; the row keeps its prior content',
        attributes: {
          'messageId': event.messageId,
          'activityType': event.activityType,
          'existingActivityType': current[idx].activityType,
        },
      );
      return current;
    }
    return [...current]..[idx] = ActivityRecord(
        messageId: event.messageId,
        activityType: event.activityType,
        content: eventContent,
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

// A delta this fold cannot place (no prior snapshot, or an activityType that
// disagrees with the record's) is dropped without minting a drop tile. This
// is intentionally asymmetric with `_processStateSnapshot`, which throws on
// bad input and lets the orchestrator append a visible
// `DroppedEventMessage`. The error-level log is the backend-escalation
// channel; UI consumers see no change.
//
// The two branches earn that silence differently. On an activityType
// mismatch a row already exists and stays usable at its prior state — it
// simply doesn't advance, so a tile would be visual noise. On a missing
// prior snapshot there is no record and no row, so nothing on screen says
// the event arrived; the log is the only trace. That is the weaker case,
// and it is tolerated because the log is an escalation channel a producer
// emitting deltas would surface on before a reader noticed a gap. Note that
// dropping is a choice rather than the only reading: a patch against an
// absent record could equally materialise one from `{}`, which is what the
// backend's own parser does.
List<ActivityRecord> _applyDelta(
  List<ActivityRecord> current,
  ActivityDeltaEvent event,
  Logger log,
) {
  final idx = current.indexWhere((a) => a.messageId == event.messageId);
  if (idx < 0) {
    log.error(
      'ActivityDeltaEvent dropped: no prior snapshot for messageId',
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
