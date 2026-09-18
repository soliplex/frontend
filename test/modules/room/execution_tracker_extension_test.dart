import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:soliplex_frontend/src/modules/room/execution_tracker_extension.dart';
import 'package:soliplex_frontend/src/modules/room/tracker_registry.dart';

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
      id: noResponseMessageId(runId),
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

  test('rekeys awaiting tracker when terminal state has synthesized message',
      () {
    // Seed an awaiting tracker by entering RunningState with AwaitingText.
    session.emitRunState(
      const RunningState(
        threadKey: _key,
        runId: _runId,
        conversation: Conversation(threadId: _threadId),
        streaming: AwaitingText(),
      ),
    );
    expect(ext.trackers.containsKey(awaitingTrackerKey), isTrue);

    final synthesized = _synthesized(_runId);
    session.emitRunState(
      CancelledState.duringRun(
        threadKey: _key,
        runId: _runId,
        conversation: _conversationWith([synthesized]),
      ),
    );

    expect(ext.trackers.containsKey(awaitingTrackerKey), isFalse);
    expect(ext.trackers.containsKey(noResponseMessageId(_runId)), isTrue);
  });

  test('skips rekey when runId is null (e.g., pre-run failure)', () {
    session.emitRunState(
      const RunningState(
        threadKey: _key,
        runId: _runId,
        conversation: Conversation(threadId: _threadId),
        streaming: AwaitingText(),
      ),
    );
    expect(ext.trackers.containsKey(awaitingTrackerKey), isTrue);

    // Pre-run failure: runId is null and no synthesized message exists in
    // the conversation. The rekey is skipped instead of crashing.
    session.emitRunState(
      FailedState.preRun(
        threadKey: _key,
        reason: FailureReason.internalError,
        error: 'pre-run',
      ),
    );

    // The awaiting tracker is frozen on terminal but not renamed.
    expect(ext.trackers.containsKey(awaitingTrackerKey), isTrue);
    expect(
      ext.trackers.containsKey(noResponseMessageId(_runId)),
      isFalse,
    );
  });

  test('skips rekey when synthesized message is not in the conversation', () {
    session.emitRunState(
      const RunningState(
        threadKey: _key,
        runId: _runId,
        conversation: Conversation(threadId: _threadId),
        streaming: AwaitingText(),
      ),
    );

    // Conversation has no synthesized "no response" message — the run
    // produced an actual reply that's already attached. No rekey needed.
    session.emitRunState(
      CompletedState(
        threadKey: _key,
        runId: _runId,
        conversation: _conversationWith([
          TextMessage.create(
            id: 'asst-1',
            user: ChatUser.assistant,
            text: 'hello',
          ),
        ]),
      ),
    );

    expect(ext.trackers.containsKey(awaitingTrackerKey), isTrue);
    expect(
      ext.trackers.containsKey(noResponseMessageId(_runId)),
      isFalse,
    );
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

  test('a run cut off while reasoning keeps its band on the tile that commits',
      () {
    // The reply opened but never spoke, so it holds no band; a terminal
    // arriving here commits it anyway, for the reasoning the user watched
    // stream. That tile is the only thing standing for the run, so the band
    // has to reach it.
    session.emitRunState(
      const RunningState(
        threadKey: _key,
        runId: _runId,
        conversation: Conversation(threadId: _threadId),
        streaming: AwaitingText(bufferedThinkingText: 'reasoning'),
      ),
    );
    session.emitRunState(
      RunningState(
        threadKey: _key,
        runId: _runId,
        conversation: const Conversation(threadId: _threadId),
        streaming: const TextStreaming(
          messageId: 'asst-1',
          user: ChatUser.assistant,
          text: '',
          thinkingText: 'reasoning',
        ),
      ),
    );

    // cancelRun commits the partial reply under its own id.
    session.emitRunState(
      CancelledState.duringRun(
        threadKey: _key,
        runId: _runId,
        conversation: _conversationWith([
          TextMessage.create(
            id: 'asst-1',
            user: ChatUser.assistant,
            text: '',
            thinkingText: 'reasoning',
          ),
        ]),
      ),
    );

    expect(
      ext.trackers['asst-1'],
      isNotNull,
      reason: 'the committed tile renders the reasoning; its execution steps '
          'must not be left under a key nothing reads',
    );
  });

  test('a run whose reply spoke reports no handover', () {
    // The reply took the band by speaking, so there is nothing to hand over.
    // Asking anyway makes the registry report a tile losing its timeline on
    // every ordinary run, which is how a diagnostics buffer becomes unreadable.
    final sink = _RecordingSink();
    LogManager.instance.addSink(sink);
    addTearDown(() => LogManager.instance.removeSink(sink));

    session.emitRunState(
      const RunningState(
        threadKey: _key,
        runId: _runId,
        conversation: Conversation(threadId: _threadId),
        streaming: TextStreaming(
          messageId: 'asst-1',
          user: ChatUser.assistant,
          text: 'The answer.',
        ),
      ),
    );
    session.emitRunState(
      CompletedState(
        threadKey: _key,
        runId: _runId,
        conversation: _conversationWith([
          TextMessage.create(
            id: 'asst-1',
            user: ChatUser.assistant,
            text: 'The answer.',
          ),
        ]),
      ),
    );

    expect(ext.trackers['asst-1'], isNotNull);
    expect(sink.warnings, isEmpty);
  });
}

/// Captures warnings the registry emits, so a report that fires on an ordinary
/// run is a test failure rather than noise nobody reads.
class _RecordingSink implements LogSink {
  final List<LogRecord> records = [];

  List<LogRecord> get warnings =>
      records.where((r) => r.level == LogLevel.warning).toList();

  @override
  void write(LogRecord record) => records.add(record);

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}
