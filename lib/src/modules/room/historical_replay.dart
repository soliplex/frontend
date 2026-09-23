import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'execution_step.dart';
import 'execution_tracker.dart';
import 'response_segmenter.dart';

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
/// Work buckets by model response, as [ResponseSegmenter] decides it: a
/// response ends when the one after a tool result starts. Everything collects
/// under
/// [noResponseMessageId] for the run — which names the tile that run is given
/// if nothing speaks for its work — and the first message to speak in a
/// response takes that response's bucket when the response ends. A response
/// that says nothing leaves its work where it is, so the next one to speak
/// takes that too.
///
/// A message that never says anything takes no bucket. A response that begins
/// with a tool call mints one purely to give that call a parent, and the
/// timeline does not show it, so work left there would render nowhere. A
/// message whose `TEXT_MESSAGE_END` is not stored takes none either: the
/// history replay commits a reply only at its end, so a band keyed to it would
/// name a tile that is never shown.
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
    // A message only takes the work once it has said something, and only if
    // it is shown — which on reload means its end was stored. Live, both are
    // known as they happen; here the whole run is in hand, so the messages that
    // speak can be read off it first.
    final ended = {
      for (final raw in bundle.events)
        if (raw is TextMessageEndEvent) raw.messageId,
    };
    final spoke = <String>{
      for (final raw in bundle.events)
        if (raw is TextMessageContentEvent &&
            raw.delta.trim().isNotEmpty &&
            ended.contains(raw.messageId))
          raw.messageId,
    };

    // Everything collects under the key that names the tile this run is given
    // if it never speaks, and moves to whichever message speaks for it.
    final unclaimed = noResponseMessageId(bundle.runId);
    final segmenter = ResponseSegmenter();

    void handOver(String? takes) {
      // A response that said nothing leaves its work where it is, so the next
      // response to speak takes that too. This is what merges a declaration's
      // round into the reply it was opened for.
      if (takes == null) return;
      final events = buckets.remove(unclaimed);
      final rawEvents = rawBuckets.remove(unclaimed);
      if (events != null) buckets[takes] = events;
      if (rawEvents != null) rawBuckets[takes] = rawEvents;
    }

    for (final raw in bundle.events) {
      final execEvent = bridgeOrLog(raw);
      // Live reads the same two signals — a message starting to speak, and an
      // execution event that opens a response.
      if (raw is TextMessageStartEvent &&
          raw.role == TextMessageRole.assistant &&
          spoke.contains(raw.messageId)) {
        handOver(segmenter.speaks(raw.messageId));
      }
      if (execEvent != null) handOver(segmenter.arrives(execEvent));

      rawBuckets.putIfAbsent(unclaimed, () => []).add(raw);
      if (execEvent != null) {
        buckets
            .putIfAbsent(unclaimed, () => [])
            .add((event: execEvent, timestamp: raw.timestamp));
      }
    }
    // The run ended, so the response being filled ends with it and whoever
    // spoke in it takes the work. Whatever it was filling is the bucket no
    // terminal event accounted for.
    final takes = segmenter.ends();
    endedOn.add(takes ?? unclaimed);
    handOver(takes);
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
/// Read from the raw events rather than the bridged ones because the event that
/// opens a stretch can bridge to nothing: `RUN_STARTED` for a run's first
/// response, and a speaking reply's `TEXT_MESSAGE_START` for a later one.
/// Anchoring on the first *bridged* event would start the clock at the
/// response's first thinking or tool event, subtracting the wait before it from
/// every figure in that response.
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
