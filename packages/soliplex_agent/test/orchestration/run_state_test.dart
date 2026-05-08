import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:test/test.dart';

const ThreadKey _key = (
  serverId: 'srv-1',
  roomId: 'room-1',
  threadId: 'thread-1',
);

void main() {
  final conversation = Conversation.empty(threadId: _key.threadId);
  const streaming = AwaitingText();

  group('FailedState', () {
    test('startedRun is true for duringRun, false for preRun', () {
      const during = FailedState.duringRun(
        threadKey: _key,
        runId: 'run-1',
        reason: FailureReason.serverError,
        error: 'boom',
      );
      const pre = FailedState.preRun(
        threadKey: _key,
        reason: FailureReason.internalError,
        error: 'oops',
      );
      expect(during.startedRun, isTrue);
      expect(pre.startedRun, isFalse);
    });

    test('requireRunId returns the id for duringRun', () {
      const state = FailedState.duringRun(
        threadKey: _key,
        runId: 'run-1',
        reason: FailureReason.serverError,
        error: 'boom',
      );
      expect(state.requireRunId(), equals('run-1'));
    });

    test('requireRunId throws StateError for preRun', () {
      const state = FailedState.preRun(
        threadKey: _key,
        reason: FailureReason.internalError,
        error: 'oops',
      );
      expect(state.requireRunId, throwsStateError);
    });
  });

  group('CancelledState', () {
    test('startedRun is true for duringRun, false for preRun', () {
      const during = CancelledState.duringRun(
        threadKey: _key,
        runId: 'run-1',
      );
      const pre = CancelledState.preRun(threadKey: _key);
      expect(during.startedRun, isTrue);
      expect(pre.startedRun, isFalse);
    });

    test('requireRunId returns the id for duringRun', () {
      const state = CancelledState.duringRun(
        threadKey: _key,
        runId: 'run-1',
      );
      expect(state.requireRunId(), equals('run-1'));
    });

    test('requireRunId throws StateError for preRun', () {
      const state = CancelledState.preRun(threadKey: _key);
      expect(state.requireRunId, throwsStateError);
    });
  });

  group('exhaustive switch', () {
    test('all subtypes are matchable', () {
      // A new RunState subtype must force a compile error here so callers
      // that rely on exhaustive matching (e.g. RunOrchestrator._isTerminal,
      // cancelRun) get a deliberate decision rather than silent fallthrough.
      final states = <RunState>[
        const IdleState(),
        RunningState(
          threadKey: _key,
          runId: 'run-1',
          conversation: conversation,
          streaming: streaming,
        ),
        CompletedState(
          threadKey: _key,
          runId: 'run-1',
          conversation: conversation,
        ),
        ToolYieldingState(
          threadKey: _key,
          runId: 'run-1',
          conversation: conversation,
          pendingToolCalls: const [],
          toolDepth: 0,
        ),
        const FailedState.preRun(
          threadKey: _key,
          reason: FailureReason.internalError,
          error: 'oops',
        ),
        const CancelledState.preRun(threadKey: _key),
      ];

      for (final state in states) {
        final label = switch (state) {
          IdleState() => 'idle',
          RunningState() => 'running',
          CompletedState() => 'completed',
          ToolYieldingState() => 'yielding',
          FailedState() => 'failed',
          CancelledState() => 'cancelled',
        };
        expect(label, isNotEmpty);
      }
    });
  });
}
