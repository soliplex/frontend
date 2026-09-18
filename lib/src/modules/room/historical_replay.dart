import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'execution_tracker.dart';

/// Signature for the per-event AG-UI → execution-event bridger. The
/// production implementation is the top-level [bridgeBaseEvent] from
/// `soliplex_agent`; tests inject throwing variants to exercise the
/// per-event catch in [replayToTrackers].
typedef ExecutionBridge = ExecutionEvent? Function(BaseEvent event);

final Logger _logger =
    LogManager.instance.getLogger('soliplex_frontend.historical_replay');

/// Keys in [trackers] holding events that no message in [shownMessageIds]
/// will render.
///
/// Bucketing routes a stretch nothing spoke for to the run's no-response key,
/// on the expectation that the chat-message side synthesized a tile there.
/// Nothing makes the two agree, so this asks: every band is meant to reach a
/// tile, which is the rule `TrackerRegistry.onRunTerminated` applies to a run
/// as it happens, asked here of one being rebuilt.
///
/// A band holding nothing is not a loss — every run ends with one, and it
/// renders nothing wherever it lands.
List<String> unclaimedBands(
  Map<String, ExecutionTracker> trackers,
  Set<String> shownMessageIds,
) =>
    [
      for (final entry in trackers.entries)
        if (entry.value.timeline.value.isNotEmpty &&
            !shownMessageIds.contains(entry.key))
          entry.key,
    ];

/// Replays stored AG-UI event bundles into one frozen [ExecutionTracker]
/// per assistant message, keyed by that message's id.
///
/// One rule decides where an event goes. A bucket opens when a message
/// speaks — an assistant `TEXT_MESSAGE_START` whose id later carries text,
/// since one that never does was opened to name a tool call's parent rather
/// than to reply — and closes when that message has said its piece. Events
/// arriving with no bucket open are held, and drain into the next one to
/// open.
///
/// A bundle that yielded to a tool without ever speaking keeps holding what
/// it collected, so a turn continuing in another run arrives whole. Any
/// other bundle keeps its own tail: it buckets under [noResponseMessageId]
/// for that run, where the chat-message side synthesizes a tile for a run
/// that ended without replying.
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
  // Events with nothing said for them yet, held until a message in the same
  // bundle speaks and absorbs them. What a bundle does not place goes to its
  // own run's no-response key, so nothing crosses a run boundary.
  final pending = <TimedExecutionEvent>[];
  final pendingRaw = <BaseEvent>[];

  /// Routes what nothing has spoken for to [runId]'s no-response key, where
  /// the tile for a run that ended without replying is looked for.
  void flushPendingTo(String runId) {
    if (pending.isEmpty && pendingRaw.isEmpty) return;
    final synthesizedId = noResponseMessageId(runId);
    buckets.putIfAbsent(synthesizedId, () => []).addAll(pending);
    rawBuckets.putIfAbsent(synthesizedId, () => []).addAll(pendingRaw);
    pending.clear();
    pendingRaw.clear();
  }

  ExecutionEvent? bridgeOrLog(BaseEvent raw) {
    try {
      return bridge(raw);
    } on Object catch (e, st) {
      _logger.error(
        'bridge threw on ${raw.runtimeType}; event skipped',
        attributes: {'failure': describeFailure(e)},
        stackTrace: st,
      );
      return null;
    }
  }

  for (final bundle in runs) {
    // Ids that carried text. A message that never receives any was opened
    // only to name a tool call's `parentMessageId`, so it takes no bucket and
    // its stretch flows to the reply that follows — the rule `TrackerRegistry`
    // applies live, mirrored here so a reloaded thread groups the same way.
    // A delta of nothing, or of whitespace, leaves nothing to read and so
    // does not count.
    final spokenIds = {
      for (final e in bundle.events)
        if (e is TextMessageContentEvent && e.delta.trim().isNotEmpty)
          e.messageId,
    };
    bool opensABucket(TextMessageStartEvent e) =>
        e.role == TextMessageRole.assistant && spokenIds.contains(e.messageId);
    String? currentMessageId;
    for (final raw in bundle.events) {
      if (raw is TextMessageStartEvent && opensABucket(raw)) {
        final messageId = raw.messageId;
        currentMessageId = messageId;
        buckets.putIfAbsent(messageId, () => []);
        final rawBucket = rawBuckets.putIfAbsent(messageId, () => []);
        if (pending.isNotEmpty) {
          buckets[messageId]!.addAll(pending);
          pending.clear();
        }
        // Drained on its own condition: the raw events preceding a reply
        // belong to its stretch whether or not any of them bridged, and the
        // run's own `RUN_STARTED` — which bridges to nothing — is what
        // anchors the reply's offsets.
        if (pendingRaw.isNotEmpty) {
          rawBucket.addAll(pendingRaw);
          pendingRaw.clear();
        }
      }

      final execEvent = bridgeOrLog(raw);
      if (currentMessageId != null) {
        rawBuckets.putIfAbsent(currentMessageId, () => []).add(raw);
        if (execEvent != null) {
          buckets
              .putIfAbsent(currentMessageId, () => [])
              .add((event: execEvent, timestamp: raw.timestamp));
        }
        // The message has said its piece; what follows belongs to the next
        // thing said, not to this one.
        if (raw is TextMessageEndEvent && raw.messageId == currentMessageId) {
          currentMessageId = null;
        }
      } else {
        pendingRaw.add(raw);
        if (execEvent != null) {
          pending.add((event: execEvent, timestamp: raw.timestamp));
        }
      }
    }

    // Whatever this bundle did not place belongs to the run that produced it,
    // and goes where the tile for a run that ended without replying is looked
    // for. Deciding instead that some bundles hand their tail to whatever
    // speaks next meant guessing that the turn continued in another run; a
    // continuation declares `parent_run_id`, which this client neither sets
    // nor reads, so the guess read the shape of the events and put an
    // abandoned run's work above the answer to the next question asked. The
    // live path carries nothing across a run either.
    flushPendingTo(bundle.runId);
  }

  return {
    for (final entry in buckets.entries)
      entry.key: ExecutionTracker.historical(
        events: entry.value,
        origin: _bucketOrigin(rawBuckets[entry.key] ?? const []),
        activities: _foldActivities(rawBuckets[entry.key] ?? const []),
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
