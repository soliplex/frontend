import 'dart:developer' as developer;

import 'package:soliplex_agent/soliplex_agent.dart';

import 'execution_tracker.dart';

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
///   next normal bundle's first assistant message absorbs them — the
///   live path tracks the same way (the active tracker at tool dispatch
///   captures the call).
/// - **No-response**: neither assistant `TextMessageStart` nor
///   `ToolCallStart`. Bucket events (including any prior pending) under
///   `'$noResponseIdPrefix${bundle.runId}'` so the synthesized
///   no-response tile has a tracker to attach to.
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
      // Tool-yield: events flow to hoisted pending, no bucket created.
      // Next normal bundle's first assistant message will absorb them.
      for (final raw in bundle.events) {
        final execEvent = bridgeBaseEvent(raw);
        if (execEvent == null) continue;
        pending.add(execEvent);
      }
    } else {
      // No-response: no assistant start, no tool call. Bucket events
      // under the synthesized no-response message id so its captured
      // thinking attaches to the rendered tile.
      final synthesizedId = '$noResponseIdPrefix${bundle.runId}';
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

  // TODO(no-response-tool-yield): Leftover `pending` events are dropped
  // here. This loses data when the last bundle in a thread is a
  // tool-yield (has ToolCallStartEvent, no assistant TextMessageStart)
  // and no follow-up bundle ever arrives.
  //
  // To preserve them, a post-pass would need to:
  //   1. Detect the case after the bundle loop completes.
  //   2. Bucket leftover `pending` under
  //      `'${noResponseIdPrefix}${lastBundle.runId}'`.
  //   3. Inject a corresponding synthesized `TextMessage` into
  //      `history.messages` so the tracker has a tile to attach to.
  //
  // Skipped because the case requires global knowledge of the stream end,
  // which breaks the event-driven contract used by the rest of synthesis.
  //
  // Reproduction recipe:
  //   1. Open a thread; send a prompt that triggers a tool call.
  //   2. Wait for the model to start the tool yield (thinking + ToolCallStart).
  //   3. Force-quit the app, kill the network, or otherwise abort before the
  //      tool result is submitted and a follow-up run completes.
  //   4. Re-open the thread. The yielding run's thinking will be missing.
  if (pending.isNotEmpty) {
    developer.log(
      'replayToTrackers: dropping ${pending.length} unattached events from '
      'a trailing tool-yield bundle (no follow-up bundle). See '
      'TODO(no-response-tool-yield) above.',
      name: 'soliplex_frontend.historical_replay',
      level: 900,
    );
  }

  return {
    for (final entry in buckets.entries)
      entry.key: ExecutionTracker.historical(events: entry.value),
  };
}
