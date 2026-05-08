import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:test/test.dart';

const ThreadKey _key = (
  serverId: 'srv-1',
  roomId: 'room-1',
  threadId: 'thread-1',
);

const ThreadKey _otherKey = (
  serverId: 'srv-2',
  roomId: 'room-2',
  threadId: 'thread-2',
);

void main() {
  final conversation = Conversation.empty(threadId: _key.threadId);
  const streaming = AwaitingText();

  group('IdleState', () {
    test('two instances compare equal', () {
      // Documents that IdleState falls back through to value equality
      // rather than identity; consumers diffing states get sensible
      // results without having to reach for a singleton instance.
      expect(const IdleState(), equals(const IdleState()));
    });
  });

  group('RunningState', () {
    test('inequality with different runId', () {
      final stateA = RunningState(
        threadKey: _key,
        runId: 'run-1',
        conversation: conversation,
        streaming: streaming,
      );
      final stateB = RunningState(
        threadKey: _key,
        runId: 'run-2',
        conversation: conversation,
        streaming: streaming,
      );
      expect(stateA, isNot(equals(stateB)));
    });

    test('copyWith replaces conversation; runId and threadKey preserved', () {
      final original = RunningState(
        threadKey: _key,
        runId: 'run-1',
        conversation: conversation,
        streaming: streaming,
      );
      final updated = conversation.withStatus(const Running(runId: 'run-1'));
      final copied = original.copyWith(conversation: updated);

      expect(copied.conversation, equals(updated));
      expect(copied.runId, equals('run-1'));
      expect(copied.threadKey, equals(_key));
    });

    test('copyWith with no args returns equal state', () {
      final original = RunningState(
        threadKey: _key,
        runId: 'run-1',
        conversation: conversation,
        streaming: streaming,
      );
      expect(original.copyWith(), equals(original));
    });
  });

  group('CompletedState', () {
    test('inequality with different threadKey', () {
      final stateA = CompletedState(
        threadKey: _key,
        runId: 'run-1',
        conversation: conversation,
      );
      final stateB = CompletedState(
        threadKey: _otherKey,
        runId: 'run-1',
        conversation: conversation,
      );
      expect(stateA, isNot(equals(stateB)));
    });
  });

  group('FailedState', () {
    test('inequality when conversation differs', () {
      const stateA = FailedState.preRun(
        threadKey: _key,
        reason: FailureReason.networkLost,
        error: 'timeout',
      );
      final stateB = FailedState.preRun(
        threadKey: _key,
        reason: FailureReason.networkLost,
        error: 'timeout',
        conversation: conversation,
      );
      expect(stateA, isNot(equals(stateB)));
    });

    test('duringRun discriminator preserves runId', () {
      const stateA = FailedState.duringRun(
        threadKey: _key,
        runId: 'run-1',
        reason: FailureReason.serverError,
        error: 'boom',
      );
      const stateC = FailedState.duringRun(
        threadKey: _key,
        runId: 'run-2',
        reason: FailureReason.serverError,
        error: 'boom',
      );
      expect(stateA, isNot(equals(stateC)));
    });

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
    test('duringRun discriminator preserves runId', () {
      const stateA = CancelledState.duringRun(threadKey: _key, runId: 'run-1');
      const stateC = CancelledState.duringRun(threadKey: _key, runId: 'run-2');
      expect(stateA, isNot(equals(stateC)));
    });

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

  group('ToolYieldingState', () {
    final pendingTools = [const ToolCallInfo(id: 'tc-1', name: 'search')];

    test('inequality with different toolDepth', () {
      final stateA = ToolYieldingState(
        threadKey: _key,
        runId: 'run-1',
        conversation: conversation,
        pendingToolCalls: pendingTools,
        toolDepth: 0,
      );
      final stateB = ToolYieldingState(
        threadKey: _key,
        runId: 'run-1',
        conversation: conversation,
        pendingToolCalls: pendingTools,
        toolDepth: 1,
      );
      expect(stateA, isNot(equals(stateB)));
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
