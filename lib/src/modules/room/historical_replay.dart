import 'package:soliplex_agent/soliplex_agent.dart';

import 'execution_tracker.dart';

/// Replays stored AG-UI event bundles into one frozen [ExecutionTracker]
/// per assistant message, keyed by that message's id.
///
/// Events that land in the run before the first assistant
/// `TEXT_MESSAGE_START` are buffered and attached to the next assistant
/// message encountered. Events between two assistant messages (e.g.
/// tool-use round-trips) attach to the preceding message — matching the
/// live path, where the active tracker at tool dispatch captures the
/// tool call.
///
/// Bundles whose run never produces an assistant message yield no
/// tracker; their events are dropped rather than grafted onto an
/// unrelated bucket.
Map<String, ExecutionTracker> replayToTrackers(List<RunEventBundle> runs) {
  final buckets = <String, List<ExecutionEvent>>{};

  for (final bundle in runs) {
    String? currentMessageId;
    final pending = <ExecutionEvent>[];

    for (final raw in bundle.events) {
      if (raw is TextMessageStartEvent &&
          raw.role == TextMessageRole.assistant) {
        final messageId = raw.messageId;
        currentMessageId = messageId;
        final bucket = buckets.putIfAbsent(messageId, () => []);
        if (pending.isNotEmpty) {
          bucket.addAll(pending);
          pending.clear();
        }
      }

      final execEvent = bridgeBaseEvent(raw);
      if (execEvent == null) continue;

      if (currentMessageId != null) {
        buckets.putIfAbsent(currentMessageId, () => []).add(execEvent);
      } else {
        pending.add(execEvent);
      }
    }
  }

  return {
    for (final entry in buckets.entries)
      entry.key: ExecutionTracker.historical(events: entry.value),
  };
}
