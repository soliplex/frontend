import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/historical_replay.dart';
import 'package:soliplex_frontend/src/modules/room/tracker_registry.dart';

import '../../helpers/test_logger.dart';

/// Which band each step landed in, ignoring bands that show nothing — the
/// live path leaves an empty gap open at the end of a run and replay
/// materializes the same gap under the run's no-response key.
Map<String, List<String>> _bands(Map<String, ExecutionTracker> trackers) => {
      for (final entry in trackers.entries)
        if (entry.value.steps.value.isNotEmpty)
          entry.key: [for (final step in entry.value.steps.value) step.label],
    };

/// Groups [events] the way a live run does: `processEvent` drives the
/// streaming state into the registry, and the bridged event reaches the
/// tracker afterwards — the order `RunOrchestrator` emits them in.
Map<String, List<String>> _live(List<BaseEvent> events) {
  final registry = TrackerRegistry(logger: testLogger());
  addTearDown(registry.dispose);
  final signal = Signal<ExecutionEvent?>(null);
  final activities = Signal<List<ActivityRecord>>(const []);

  var conversation = Conversation.empty(threadId: 'thread-1');
  StreamingState streaming = const AwaitingText();
  for (final event in events) {
    final result = processEvent(conversation, streaming, event);
    conversation = result.conversation;
    streaming = result.streaming;
    registry.onStreaming(streaming, signal, activities);
    final bridged = bridgeBaseEvent(event);
    if (bridged != null) signal.value = bridged;
  }
  // What `ExecutionTrackerExtension` does at every terminal, before freezing:
  // a band nothing spoke for moves onto the tile synthesized for the run.
  // Replay reaches the same key by computing it directly, so leaving this out
  // would make the two disagree for reasons production does not have.
  final synthesized = noResponseMessageId('run-1');
  if (conversation.messages.any((message) => message.id == synthesized)) {
    registry.claimOpenBand(synthesized);
  }
  registry.onRunTerminated();

  return _bands(registry.trackers);
}

Map<String, List<String>> _replayed(List<BaseEvent> events) => _bands(
      replayToTrackers([RunEventBundle(runId: 'run-1', events: events)]),
    );

/// A run that reasons, says something, works, declares a second tool call and
/// finally answers — every shape the grouping rule has to decide, in one
/// sequence.
final _events = <BaseEvent>[
  RunStartedEvent(threadId: 'thread-1', runId: 'run-1'),
  const ReasoningMessageStartEvent(messageId: 'reason-1'),
  const ReasoningMessageContentEvent(messageId: 'reason-1', delta: 'planning'),
  const ReasoningMessageEndEvent(messageId: 'reason-1'),
  const TextMessageStartEvent(messageId: 'msg-1'),
  const TextMessageContentEvent(
      messageId: 'msg-1', delta: 'Let me look that up.'),
  const TextMessageEndEvent(messageId: 'msg-1'),
  const ToolCallStartEvent(
    toolCallId: 'tc-1',
    toolCallName: 'search',
    parentMessageId: 'msg-1',
  ),
  const ToolCallEndEvent(toolCallId: 'tc-1'),
  const ToolCallResultEvent(
    messageId: 'result-1',
    toolCallId: 'tc-1',
    content: 'ok',
  ),
  const ReasoningMessageStartEvent(messageId: 'reason-2'),
  const ReasoningMessageContentEvent(messageId: 'reason-2', delta: 'one more'),
  const ReasoningMessageEndEvent(messageId: 'reason-2'),
  const TextMessageStartEvent(messageId: 'decl-1'),
  const TextMessageEndEvent(messageId: 'decl-1'),
  const ToolCallStartEvent(
    toolCallId: 'tc-2',
    toolCallName: 'fetch_document',
    parentMessageId: 'decl-1',
  ),
  const ToolCallEndEvent(toolCallId: 'tc-2'),
  const ToolCallResultEvent(
    messageId: 'result-2',
    toolCallId: 'tc-2',
    content: 'ok',
  ),
  const TextMessageStartEvent(messageId: 'msg-2'),
  const TextMessageContentEvent(messageId: 'msg-2', delta: 'The answer.'),
  const TextMessageEndEvent(messageId: 'msg-2'),
  const RunFinishedEvent(threadId: 'thread-1', runId: 'run-1'),
];

/// A run that works and never speaks: the shape where live and replay reach
/// the same key by completely different means — replay computes it, live
/// depends on the domain having synthesized a tile to rename onto.
final _silentRun = <BaseEvent>[
  RunStartedEvent(threadId: 'thread-1', runId: 'run-1'),
  const ReasoningMessageStartEvent(messageId: 'reason-1'),
  const ReasoningMessageContentEvent(messageId: 'reason-1', delta: 'looking'),
  const ReasoningMessageEndEvent(messageId: 'reason-1'),
  const TextMessageStartEvent(messageId: 'decl-1'),
  const TextMessageEndEvent(messageId: 'decl-1'),
  const ToolCallStartEvent(
    toolCallId: 'tc-1',
    toolCallName: 'search',
    parentMessageId: 'decl-1',
  ),
  const ToolCallEndEvent(toolCallId: 'tc-1'),
  const ToolCallResultEvent(
    messageId: 'result-1',
    toolCallId: 'tc-1',
    content: 'ok',
  ),
  const RunFinishedEvent(threadId: 'thread-1', runId: 'run-1'),
];

void main() {
  // The rule — a band is the stretch between one thing the assistant said and
  // the next — is implemented twice: `TrackerRegistry` reads the live
  // streaming state, `replayToTrackers` reads stored events. They share no
  // code, so a change to one can silently regroup a thread on reload only.
  //
  // Compared on which band each step landed in, which is what the rule
  // decides. Both sides also end a run holding an empty band — live under the
  // awaiting key, replay under the run's no-response key — and neither
  // renders; `_bands` leaves those out rather than asserting one shape for
  // two things that show nothing.
  test('live and replay group the same run identically', () {
    expect(_live(_events), equals(_replayed(_events)));
  });

  test('live and replay group a run that never speaks identically', () {
    expect(_live(_silentRun), equals(_replayed(_silentRun)));
  });

  test('a run that never speaks puts its band on the tile for it', () {
    expect(
      _replayed(_silentRun),
      equals({
        noResponseMessageId('run-1'): ['Thinking', 'search'],
      }),
    );
  });

  test('the run groups as the rule describes', () {
    // Pinned separately so the equivalence test above cannot pass by both
    // sides being wrong in the same way.
    expect(
      _replayed(_events),
      equals({
        'msg-1': ['Thinking'],
        'msg-2': ['search', 'Thinking', 'fetch_document'],
      }),
    );
  });
}
