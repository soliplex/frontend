import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/room/execution_tracker_extension.dart';

import '../../helpers/test_logger.dart';

const _threadId = 'thread-1';
const _key = (serverId: 'server-1', roomId: 'room-1', threadId: _threadId);
const _runId = 'run-1';

class _FakeSession implements AgentSession {
  final Signal<RunState> _runState = Signal<RunState>(const IdleState());
  final Signal<ExecutionEvent?> _events = Signal<ExecutionEvent?>(null);
  final Signal<List<ActivityRecord>> _activities =
      Signal<List<ActivityRecord>>(const []);

  @override
  ReadonlySignal<RunState> get runState => _runState.readonly();

  @override
  ReadonlySignal<ExecutionEvent?> get lastExecutionEvent => _events.readonly();

  @override
  ReadonlySignal<List<ActivityRecord>> get conversationActivities =>
      _activities.readonly();

  void emitRunState(RunState state) => _runState.value = state;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_FakeSession.${invocation.memberName}');
}

Conversation _conversationWith(List<ChatMessage> messages) =>
    Conversation.empty(threadId: _threadId).copyWith(messages: messages);

NoResponseTile _synthesized(String runId) => NoResponseTile.cancelled(
      runId: runId,
      thinkingText: 'reasoning',
    );

void main() {
  late _FakeSession session;
  late ExecutionTrackerExtension ext;

  setUp(() async {
    session = _FakeSession();
    ext = ExecutionTrackerExtension(logger: testLogger());
    await ext.onAttach(session);
  });

  tearDown(() => ext.onDispose());

  test("a run that never speaks keeps its band under its own run", () {
    // The key is the run's from the moment the band exists, so the tile that
    // stands for a run with nothing else to show for it finds its work
    // already there. Nothing is renamed on the way to a terminal.
    session.emitRunState(
      const RunningState(
        threadKey: _key,
        runId: _runId,
        conversation: Conversation(threadId: _threadId),
        streaming: AwaitingText(),
      ),
    );
    expect(ext.trackers.containsKey(noResponseMessageId(_runId)), isTrue);

    session.emitRunState(
      CancelledState.duringRun(
        threadKey: _key,
        runId: _runId,
        conversation: _conversationWith([_synthesized(_runId)]),
      ),
    );

    expect(ext.trackers.containsKey(noResponseMessageId(_runId)), isTrue);
  });

  test('a terminal that names no run leaves the band where it is', () {
    session.emitRunState(
      const RunningState(
        threadKey: _key,
        runId: _runId,
        conversation: Conversation(threadId: _threadId),
        streaming: AwaitingText(),
      ),
    );

    // A pre-run failure carries no run of its own, and cannot disturb the
    // band of the run that was already going.
    session.emitRunState(
      FailedState.preRun(
        threadKey: _key,
        reason: FailureReason.internalError,
        error: 'pre-run',
      ),
    );

    expect(ext.trackers.containsKey(noResponseMessageId(_runId)), isTrue);
  });

  test('post-dispose runState arrival logs and returns; does not crash', () {
    // The teardown order in `onDispose` cancels the subscription before
    // clearing `_session`, but signals' dispatch ordering across upgrades
    // isn't a guarantee we want to rely on. Drive the post-dispose path
    // directly via `debugPushRunState` to confirm the null-check holds.
    ext.onDispose();

    expect(
      () => ext.debugPushRunState(
        CancelledState.duringRun(
          threadKey: _key,
          runId: _runId,
          conversation: _conversationWith(const []),
        ),
      ),
      returnsNormally,
    );
  });
}
