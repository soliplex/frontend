import 'package:flutter_test/flutter_test.dart';
import 'package:signals_core/signals_core.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart';

import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/execution_tracker_extension.dart';

// ---------------------------------------------------------------------------
// Fake session exposing the two signals the extension subscribes to
// ---------------------------------------------------------------------------

class _FakeSession implements AgentSession {
  final Signal<RunState> _runState = Signal(const IdleState());
  final Signal<ExecutionEvent?> _event = Signal(null);

  @override
  ReadonlySignal<RunState> get runState => _runState;

  @override
  ReadonlySignal<ExecutionEvent?> get lastExecutionEvent => _event;

  void emitRun(RunState state) => _runState.value = state;

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _threadKey = (serverId: 'srv', roomId: 'room', threadId: 'thread');

RunningState _running(StreamingState streaming) => RunningState(
      threadKey: _threadKey,
      runId: 'r1',
      conversation: const Conversation(threadId: 'thread'),
      streaming: streaming,
    );

CompletedState _completed() => const CompletedState(
      threadKey: _threadKey,
      runId: 'r1',
      conversation: Conversation(threadId: 'thread'),
    );

FailedState _failed() => const FailedState(
      threadKey: _threadKey,
      reason: FailureReason.internalError,
      error: 'fail',
    );

CancelledState _cancelled() => const CancelledState(threadKey: _threadKey);

void main() {
  group('ExecutionTrackerExtension', () {
    late ExecutionTrackerExtension ext;
    late _FakeSession session;

    setUp(() async {
      ext = ExecutionTrackerExtension();
      session = _FakeSession();
      await ext.onAttach(session);
    });

    tearDown(() => ext.onDispose());

    test('initial state is empty map', () {
      expect(ext.state, isEmpty);
      expect(ext.trackers, isEmpty);
    });

    test('RunningState with AwaitingText creates a tracker entry', () {
      session.emitRun(_running(const AwaitingText()));

      expect(ext.state, isNotEmpty);
      expect(ext.trackers, isNotEmpty);
    });

    test('tracker created for AwaitingText uses awaiting sentinel key', () {
      session.emitRun(_running(const AwaitingText()));

      expect(ext.trackers.containsKey('_awaiting'), isTrue);
    });

    test('tracker created for TextStreaming uses messageId as key', () {
      session.emitRun(
        _running(
          const TextStreaming(
            messageId: 'msg-1',
            user: ChatUser.assistant,
            text: 'hello',
          ),
        ),
      );

      expect(ext.trackers.containsKey('msg-1'), isTrue);
    });

    test('tracker entry is an ExecutionTracker', () {
      session.emitRun(_running(const AwaitingText()));

      expect(ext.trackers.values.first, isA<ExecutionTracker>());
    });

    test('CompletedState freezes the active tracker', () {
      session.emitRun(_running(const AwaitingText()));
      final tracker = ext.trackers.values.first;

      session.emitRun(_completed());

      expect(tracker.isFrozen, isTrue);
    });

    test('FailedState freezes the active tracker', () {
      session.emitRun(_running(const AwaitingText()));
      final tracker = ext.trackers.values.first;

      session.emitRun(_failed());

      expect(tracker.isFrozen, isTrue);
    });

    test('CancelledState freezes the active tracker', () {
      session.emitRun(_running(const AwaitingText()));
      final tracker = ext.trackers.values.first;

      session.emitRun(_cancelled());

      expect(tracker.isFrozen, isTrue);
    });

    test('IdleState does not create or freeze trackers', () {
      session.emitRun(const IdleState());

      expect(ext.state, isEmpty);
    });

    test('ToolYieldingState does not create or freeze trackers', () {
      session.emitRun(
        ToolYieldingState(
          threadKey: _threadKey,
          runId: 'r1',
          conversation: const Conversation(threadId: 'thread'),
          pendingToolCalls: const [],
          toolDepth: 0,
        ),
      );

      expect(ext.state, isEmpty);
    });

    test('stateSignal notifies when tracker map changes', () {
      final counts = <int>[];
      ext.stateSignal.subscribe((v) => counts.add(v.length));

      session.emitRun(_running(const AwaitingText()));

      expect(counts, contains(1));
    });

    test('state reflects tracker map after terminal state', () {
      session.emitRun(_running(const AwaitingText()));
      session.emitRun(_completed());

      expect(ext.state, isNotEmpty);
      expect(ext.state.values.first.isFrozen, isTrue);
    });

    test('namespace is execution_tracker', () {
      expect(ext.namespace, 'execution_tracker');
    });

    test('priority is 10', () {
      expect(ext.priority, 10);
    });

    test('tools is empty', () {
      expect(ext.tools, isEmpty);
    });

    test('onDispose unsubscribes — emitting after dispose does not throw', () {
      ext.onDispose();

      expect(
        () => session.emitRun(_running(const AwaitingText())),
        returnsNormally,
      );
    });
  });
}
