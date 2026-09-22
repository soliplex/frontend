import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'execution_step.dart';
import 'execution_tracker.dart';

/// Signature for the per-event AG-UI → execution-event bridger. The
/// production implementation is the top-level [bridgeBaseEvent] from
/// `soliplex_agent`; tests inject throwing variants to exercise the
/// per-event catch in [replayToTrackers].
typedef ExecutionBridge = ExecutionEvent? Function(BaseEvent event);

final Logger _logger =
    LogManager.instance.getLogger('soliplex_frontend.historical_replay');

/// Replays stored AG-UI event bundles into frozen [ExecutionTracker]s, keyed
/// by the message that owns the work or — until one speaks — by the run doing
/// it, which is how the live registry keys them too.
///
/// A run owns its work until one of its messages speaks. Everything a run
/// does before that buckets under [noResponseMessageId] for the run — which
/// names the tile that run is given if it never speaks — and the first message
/// that does speak takes it. Later messages in the same run open buckets of
/// their own, so work stays with whichever message was speaking when it
/// happened.
///
/// A message that never says anything opens no bucket. A response that begins
/// with a tool call mints one purely to give that call a parent, and the
/// timeline does not show it, so work left there would render nowhere.
///
/// The move is a move, never a copy: no run offers both its own key and a
/// message key for the same work, which is the one input the timeline cannot
/// place — both resolve to the same tile and one would have to be dropped.
///
/// Nothing is carried between runs. A run that worked and never spoke keeps
/// its work under its own key rather than handing it to whatever answers
/// next, which would file one turn's steps above another turn's reply.
///
/// A throw from [bridge] is logged at error and the offending event
/// skipped so surrounding events in the same bundle still bucket
/// correctly. The drop is deliberately UI-silent: chat-message
/// boundaries mint the drop tile; double-minting from this tracker
/// projection would surface the same backend event as two tiles.
/// [bridge] defaults to [bridgeBaseEvent] and is overridable for tests.
Map<String, ExecutionTracker> replayToTrackers(
  List<RunEventBundle> runs, {
  @visibleForTesting ExecutionBridge bridge = bridgeBaseEvent,
}) {
  final buckets = <String, List<TimedExecutionEvent>>{};
  // Parallel to `buckets`: the raw AG-UI events destined for each
  // tracker, retained so we can fold them through `applyActivityEvent`
  // at construction time. Bridging drops `ActivityDeltaEvent`, so the
  // bridged `ExecutionEvent` stream is insufficient for activity
  // reconstruction.
  final rawBuckets = <String, List<BaseEvent>>{};

  ExecutionEvent? bridgeOrLog(BaseEvent raw) {
    try {
      return bridge(raw);
    } on Object catch (e, st) {
      _logger.error(
        'bridge threw on ${raw.runtimeType}; event skipped',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  // The key each run was filling when its events ran out. Every other bucket
  // closed because the run moved on to another reply, which means its work
  // finished; only these were left open by the run ending.
  final endedOn = <String>{};

  for (final bundle in runs) {
    // A message only takes the work once it has said something. Live, that is
    // known as it happens; here the whole run is in hand, so the messages that
    // speak can be read off it first.
    final spoke = <String>{
      for (final raw in bundle.events)
        if (raw is TextMessageContentEvent && raw.delta.trim().isNotEmpty)
          raw.messageId,
    };

    // Until one of them does, the run owns its work, under the key that names
    // the tile the run is given if it never speaks at all.
    final unclaimed = noResponseMessageId(bundle.runId);
    var key = unclaimed;

    for (final raw in bundle.events) {
      if (raw is TextMessageStartEvent &&
          raw.role == TextMessageRole.assistant &&
          spoke.contains(raw.messageId) &&
          key != raw.messageId) {
        if (key == unclaimed) {
          // The first message to speak takes what the run collected waiting
          // for it — moved, never copied, so no run ever offers two bands for
          // one tile to choose between.
          final events = buckets.remove(unclaimed);
          final rawEvents = rawBuckets.remove(unclaimed);
          if (events != null) buckets[raw.messageId] = events;
          if (rawEvents != null) rawBuckets[raw.messageId] = rawEvents;
        }
        key = raw.messageId;
      }

      rawBuckets.putIfAbsent(key, () => []).add(raw);
      final execEvent = bridgeOrLog(raw);
      if (execEvent != null) {
        buckets
            .putIfAbsent(key, () => [])
            .add((event: execEvent, timestamp: raw.timestamp));
      }
    }
    endedOn.add(key);
  }

  return {
    for (final entry in buckets.entries)
      entry.key: ExecutionTracker.historical(
        events: entry.value,
        origin: _bucketOrigin(rawBuckets[entry.key] ?? const []),
        activities: _foldActivities(rawBuckets[entry.key] ?? const []),
        unfinishedAs: endedOn.contains(entry.key)
            ? StepStatus.failed
            : StepStatus.completed,
        logger: _logger,
      ),
  };
}

/// The instant a bucket's stretch of the run began, or null when none of its
/// stored events carries a time.
///
/// Read from the raw events rather than the bridged ones because the events
/// that open a stretch bridge to nothing: `RUN_STARTED` for a run's first
/// reply, and the `TEXT_MESSAGE_START` of every reply after it. A bucket that
/// absorbed a hoisted tool-yield run opens on that run's events instead, and
/// anchors there. Anchoring on the first *bridged* event would start the clock
/// at the reply's first thinking or tool event, subtracting the wait before it
/// from every figure in that reply.
int? _bucketOrigin(List<BaseEvent> raw) {
  for (final event in raw) {
    final timestamp = event.timestamp;
    if (timestamp != null) return timestamp;
  }
  return null;
}

List<ActivityRecord> _foldActivities(List<BaseEvent> events) {
  var activities = const <ActivityRecord>[];
  for (final event in events) {
    activities = applyActivityEvent(activities, event, logger: _logger);
  }
  return activities;
}
