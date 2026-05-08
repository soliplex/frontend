import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'execution_tracker.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex_frontend.historical_replay');

/// Replays stored AG-UI event bundles into one frozen [ExecutionTracker]
/// per assistant message, keyed by that message's id.
///
/// Bundle classification:
///
/// - **Normal**: contains an assistant `TextMessageStart`. Events bucket
///   under that id; any events accumulated in the hoisted `pending` from
///   prior tool-yield bundles drain into the first assistant bucket.
/// - **Tool-yield**: contains a `ToolCallStart` but no assistant
///   `TextMessageStart`. Events flow into the hoisted `pending` so the
///   next normal bundle's first assistant message absorbs them.
/// - **No-response**: neither assistant `TextMessageStart` nor
///   `ToolCallStart`. Bucket events (including any prior pending) under
///   [noResponseMessageId] for the run so the synthesized no-response
///   tile has a tracker to attach to.
Map<String, ExecutionTracker> replayToTrackers(List<RunEventBundle> runs) {
  final buckets = <String, List<ExecutionEvent>>{};
  // Hoisted across bundles: tool-yield events accumulate here until the
  // next normal bundle's first assistant message absorbs them.
  final pending = <ExecutionEvent>[];

  for (final bundle in runs) {
    final hasAssistantStart = bundle.events.any(
      (e) => e is TextMessageStartEvent && e.role == TextMessageRole.assistant,
    );
    final hasToolCall = bundle.events.any((e) => e is ToolCallStartEvent);

    if (hasAssistantStart) {
      String? currentMessageId;
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
    } else if (hasToolCall) {
      for (final raw in bundle.events) {
        final execEvent = bridgeBaseEvent(raw);
        if (execEvent == null) continue;
        pending.add(execEvent);
      }
    } else {
      final synthesizedId = noResponseMessageId(bundle.runId);
      final bucket = buckets.putIfAbsent(synthesizedId, () => []);
      if (pending.isNotEmpty) {
        bucket.addAll(pending);
        pending.clear();
      }
      for (final raw in bundle.events) {
        final execEvent = bridgeBaseEvent(raw);
        if (execEvent == null) continue;
        bucket.add(execEvent);
      }
    }
  }

  // A trailing tool-yield bundle's hoisted events have no follow-up
  // assistant message to absorb them; logged here so the case is at
  // least observable. Tracked: soliplex/frontend#221.
  if (pending.isNotEmpty) {
    _logger.warning(
      'Dropping unattached events from a trailing tool-yield bundle '
      '(no follow-up bundle).',
      attributes: {'pendingCount': pending.length},
    );
  }

  return {
    for (final entry in buckets.entries)
      entry.key:
          ExecutionTracker.historical(events: entry.value, logger: _logger),
  };
}
