import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart' show appendUserMessage;
import 'package:soliplex_logging/soliplex_logging.dart';

import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/return_to_storage.dart';
import 'package:soliplex_frontend/src/modules/room/agent_runtime_manager.dart';
import 'package:soliplex_frontend/src/modules/room/composer_draft.dart';
import 'package:soliplex_frontend/src/modules/room/execution_tracker_extension.dart';
import 'package:soliplex_frontend/src/modules/room/human_approval_extension.dart';
import 'package:soliplex_frontend/src/modules/room/lay_out_timeline.dart';
import 'package:soliplex_frontend/src/modules/room/run_registry.dart';
import 'package:soliplex_frontend/src/modules/room/thread_view_state.dart';

import '../../helpers/fakes.dart';
import '../../helpers/live_session.dart';
import '../../helpers/test_server_entry.dart';

ServerConnection _fakeConnection(FakeSoliplexApi api) => ServerConnection(
      serverId: 'test-server',
      api: api,
      agUiStreamClient: FakeAgUiStreamClient(),
    );

const _testUserId = 'iss-test#user';

/// A `rag` block in the pre-0.41 shape: whole citations, no `citation_index`.
Map<String, dynamic> _legacyRagState() => {
      'rag': <String, dynamic>{
        'citations': [
          {'document_id': 'doc-1', 'chunk_id': 'chunk-1', 'content': 'x'},
        ],
      },
    };

/// FakeSoliplexApi variant that holds getThreadHistory open until the
/// test resolves it. Used to assert observable behavior on an in-flight
/// request (notably cancel-token cancellation on auth flip).
class _PendingHistoryApi extends FakeSoliplexApi {
  Completer<ThreadHistory>? _pending;
  CancelToken? capturedToken;
  ReplayObserver? _observer;

  @override
  Future<ThreadHistory> getThreadHistory(
    String roomId,
    String threadId, {
    CancelToken? cancelToken,
    ReplayObserver? observer,
  }) {
    capturedToken = cancelToken;
    _observer = observer;
    _pending ??= Completer<ThreadHistory>();
    return _pending!.future;
  }

  /// Answers the request with [history], having first replayed [stored] to
  /// the request's observer as the real client replays the runs it reads.
  Future<void> completeWith(
    ThreadHistory history, {
    List<StoredRun> stored = const [],
  }) async {
    if (stored.isNotEmpty) await storedHistory(stored, observer: _observer);
    _pending?.complete(history);
  }
}

/// AgentRuntime whose [spawn] always errors with [AuthException]. Used to
/// exercise the spawner's AuthException branch end-to-end from
/// `ThreadViewState.sendMessage`.
class _AuthExceptionThrowingRuntime extends AgentRuntime {
  _AuthExceptionThrowingRuntime(ServerConnection connection)
      : super(
          connection: connection,
          toolRegistryResolver: (_) async => const ToolRegistry(),
          platform: TestPlatformConstraints(),
          logger: testLogger(),
        );

  @override
  Future<AgentSession> spawn({
    required String roomId,
    required List<MessagePart> prompt,
    String? threadId,
    Duration? timeout,
    bool ephemeral = false,
    bool autoDispose = false,
    AgentSession? parent,
    Map<String, dynamic>? stateOverlay,
  }) {
    return Future<AgentSession>.error(
      const AuthException(
        statusCode: 401,
        message: 'JWT validation failed',
      ),
    );
  }
}

/// Minimal session fake for testing [ThreadViewState] signal behavior.
class _FakeAgentSession implements AgentSession {
  _FakeAgentSession({List<SessionExtension> extensions = const []})
      : _runState = Signal<RunState>(const IdleState()),
        _lastExecutionEvent = Signal<ExecutionEvent?>(null),
        _reconnectStatus = Signal<ReconnectStatus?>(null),
        _activities = Signal<List<ActivityRecord>>(const []),
        _extensions = extensions;

  final Signal<RunState> _runState;
  final Signal<ExecutionEvent?> _lastExecutionEvent;
  final Signal<ReconnectStatus?> _reconnectStatus;
  final Signal<List<ActivityRecord>> _activities;
  final Completer<AgentResult> _resultCompleter = Completer<AgentResult>();
  final List<SessionExtension> _extensions;
  bool cancelCalled = false;

  @override
  AgentSessionState get state => AgentSessionState.running;

  @override
  ReadonlySignal<RunState> get runState => _runState;

  @override
  ReadonlySignal<ExecutionEvent?> get lastExecutionEvent => _lastExecutionEvent;

  @override
  ReadonlySignal<List<ActivityRecord>> get conversationActivities =>
      _activities;

  @override
  ReadonlySignal<ReconnectStatus?> get reconnectStatus => _reconnectStatus;

  @override
  Future<AgentResult> get result => _resultCompleter.future;

  @override
  void cancel() => cancelCalled = true;

  @override
  T? getExtension<T extends SessionExtension>() {
    for (final ext in _extensions) {
      if (ext is T) return ext;
    }
    return null;
  }

  void emit(RunState state) => _runState.value = state;

  void emitExecution(ExecutionEvent event) => _lastExecutionEvent.value = event;

  void emitReconnect(ReconnectStatus? status) =>
      _reconnectStatus.value = status;

  void complete(AgentResult result) => _resultCompleter.complete(result);

  // Surface unimplemented members loudly so a new dependency from
  // ThreadViewState fails the test immediately instead of silently
  // receiving a null.
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        '_FakeAgentSession.${invocation.memberName}',
      );
}

/// Captures, for the rest of the test, the runs in progress the view chose
/// not to follow, with the reason it logged.
List<({String runId, String reason})> Function() _skippedFollows() {
  final sink = MemorySink();
  LogManager.instance.addSink(sink);
  addTearDown(() => LogManager.instance.removeSink(sink));
  return () => [
        for (final r in sink.records)
          if (r.message.startsWith('Not following a run still going'))
            (
              runId: r.attributes['runId']! as String,
              reason: r.attributes['reason']! as String,
            ),
      ];
}

/// Captures, for the rest of the test, how each followed run ended.
List<({String runId, String result})> Function() _endedFollows() {
  final sink = MemorySink();
  LogManager.instance.addSink(sink);
  addTearDown(() => LogManager.instance.removeSink(sink));
  return () => [
        for (final r in sink.records)
          if (r.message.startsWith('Followed run ended'))
            (
              runId: r.attributes['runId']! as String,
              result: r.attributes['result']! as String,
            ),
      ];
}

void main() {
  setUpAll(registerLiveSessionFallbacks);

  late StoredHistoryApi api;
  late ServerConnection connection;
  late AuthSession auth;
  late RunRegistry registry;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = StoredHistoryApi();
    connection = _fakeConnection(api);
    auth = AuthSession(refreshService: FakeTokenRefreshService());
    registry = RunRegistry(servers: emptyServers());
  });

  tearDown(() {
    registry.dispose();
  });

  group('state warnings', () {
    test('a history refresh does not bring back a dismissed warning', () async {
      api.nextThreadHistory =
          ThreadHistory(messages: const [], aguiState: _legacyRagState());
      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      await Future<void>.delayed(Duration.zero);
      state.dismissStateWarnings();

      await state.refresh();

      expect(state.stateWarnings.value, isEmpty);
      state.dispose();
    });

    test('dismissing on a disposed view does not throw', () async {
      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      await Future<void>.delayed(Duration.zero);
      state.dispose();

      expect(state.dismissStateWarnings, returnsNormally);
    });
  });

  test('fetches thread history and exposes messages', () async {
    final message = TextMessage(
      id: 'msg-1',
      user: ChatUser.user,
      createdAt: DateTime(2026, 3, 1),
      text: 'Hello',
    );
    api.nextThreadHistory = ThreadHistory(messages: [message]);

    final state = ThreadViewState(
      connection: connection,
      auth: auth,
      roomId: 'room-1',
      threadId: 'thread-1',
      registry: registry,
      followRun: neverFollowed,
      contextWindow: Signal<int?>(null),
    );

    expect(state.messages.value, isA<MessagesLoading>());

    await Future<void>.delayed(Duration.zero);

    final loaded = state.messages.value as MessagesLoaded;
    expect(loaded.messages.length, 1);
    expect(loaded.messages.first.id, 'msg-1');

    state.dispose();
  });

  test('calls onHistoryLoaded with full history after fetch', () async {
    final message = TextMessage(
      id: 'msg-1',
      user: ChatUser.user,
      createdAt: DateTime(2026, 3, 1),
      text: 'Hello',
    );
    final aguiState = <String, dynamic>{
      'rag': <String, dynamic>{
        'citation_index': <String, dynamic>{},
        'citations': <dynamic>[],
      },
    };
    api.nextThreadHistory = ThreadHistory(
      messages: [message],
      aguiState: aguiState,
    );

    ThreadHistory? capturedHistory;
    final state = ThreadViewState(
      connection: connection,
      auth: auth,
      roomId: 'room-1',
      threadId: 'thread-1',
      registry: registry,
      followRun: neverFollowed,
      contextWindow: Signal<int?>(null),
      onHistoryLoaded: (threadId, history) {
        capturedHistory = history;
      },
    );

    await Future<void>.delayed(Duration.zero);

    expect(capturedHistory, isNotNull);
    expect(capturedHistory!.aguiState, equals(aguiState));
    expect(capturedHistory!.messages.length, 1);

    state.dispose();
  });

  test('exposes failed status on fetch error', () async {
    api.nextThreadHistoryError = Exception('network error');

    final state = ThreadViewState(
      connection: connection,
      auth: auth,
      roomId: 'room-1',
      threadId: 'thread-1',
      registry: registry,
      followRun: neverFollowed,
      contextWindow: Signal<int?>(null),
    );

    await Future<void>.delayed(Duration.zero);

    expect(state.messages.value, isA<MessagesFailed>());

    state.dispose();
  });

  test('refresh error preserves loaded messages', () async {
    api.nextThreadHistory = ThreadHistory(messages: [
      TextMessage(
        id: 'msg-1',
        user: ChatUser.user,
        createdAt: DateTime(2026, 3, 1),
        text: 'Hello',
      ),
    ]);

    final state = ThreadViewState(
      connection: connection,
      auth: auth,
      roomId: 'room-1',
      threadId: 'thread-1',
      registry: registry,
      followRun: neverFollowed,
      contextWindow: Signal<int?>(null),
    );

    await Future<void>.delayed(Duration.zero);
    expect(state.messages.value, isA<MessagesLoaded>());

    // Make refresh fail.
    api.nextThreadHistory = null;
    api.nextThreadHistoryError = Exception('refresh error');
    state.refresh();

    await Future<void>.delayed(Duration.zero);

    // Should still show loaded messages.
    final status = state.messages.value;
    expect(status, isA<MessagesLoaded>());
    expect((status as MessagesLoaded).messages.length, 1);

    state.dispose();
  });

  test('a failed refresh is logged by thread, without the error text',
      () async {
    api.nextThreadHistory = ThreadHistory(messages: const []);
    final state = ThreadViewState(
      connection: connection,
      auth: auth,
      roomId: 'room-1',
      threadId: 'thread-1',
      registry: registry,
      followRun: neverFollowed,
      contextWindow: Signal<int?>(null),
    );
    await Future<void>.delayed(Duration.zero);
    final sink = MemorySink();
    LogManager.instance.addSink(sink);
    addTearDown(() => LogManager.instance.removeSink(sink));

    api.nextThreadHistory = null;
    api.nextThreadHistoryError = Exception('secret payload');
    await state.refresh();

    final record = sink.records.singleWhere(
      (r) => r.message.contains('Thread history load failed'),
    );
    expect(record.attributes['threadId'], 'thread-1');
    expect(
      '${record.message} ${record.attributes} ${record.error}',
      isNot(contains('secret')),
    );
    state.dispose();
  });

  test('streamingState and sessionState are null when idle', () async {
    api.nextThreadHistory = ThreadHistory(messages: const []);

    final state = ThreadViewState(
      connection: connection,
      auth: auth,
      roomId: 'room-1',
      threadId: 'thread-1',
      registry: registry,
      followRun: neverFollowed,
      contextWindow: Signal<int?>(null),
    );

    await Future<void>.delayed(Duration.zero);

    expect(state.streamingState.value, isNull);
    expect(state.sessionState.value, isNull);

    state.dispose();
  });

  test('updates messages when list content changes but length stays the same',
      () async {
    api.nextThreadHistory = ThreadHistory(messages: const []);

    final state = ThreadViewState(
      connection: connection,
      auth: auth,
      roomId: 'room-1',
      threadId: 'thread-1',
      registry: registry,
      followRun: neverFollowed,
      contextWindow: Signal<int?>(null),
    );

    await Future<void>.delayed(Duration.zero);
    expect(state.messages.value, isA<MessagesLoaded>());

    final session = _FakeAgentSession();
    state.attachSession(session);

    final listA = <ChatMessage>[
      TextMessage(
        id: 'msg-1',
        user: ChatUser.user,
        createdAt: DateTime(2026),
        text: 'Hello',
      ),
    ];
    final conversationA = Conversation(
      threadId: 'thread-1',
      messages: listA,
    );

    session.emit(RunningState(
      threadKey: (
        serverId: 'test-server',
        roomId: 'room-1',
        threadId: 'thread-1'
      ),
      runId: 'run-1',
      conversation: conversationA,
      streaming: const AwaitingText(),
    ));

    final loaded1 = state.messages.value as MessagesLoaded;
    expect(loaded1.messages.first.id, 'msg-1');

    // Same length, different content, different list instance.
    final listB = <ChatMessage>[
      TextMessage(
        id: 'msg-2',
        user: ChatUser.assistant,
        createdAt: DateTime(2026),
        text: 'Hi there',
      ),
    ];
    final conversationB = Conversation(
      threadId: 'thread-1',
      messages: listB,
    );

    session.emit(RunningState(
      threadKey: (
        serverId: 'test-server',
        roomId: 'room-1',
        threadId: 'thread-1'
      ),
      runId: 'run-1',
      conversation: conversationB,
      streaming: const AwaitingText(),
    ));

    final loaded2 = state.messages.value as MessagesLoaded;
    expect(loaded2.messages.first.id, 'msg-2',
        reason:
            'should update when list instance changes even with same length');

    state.dispose();
  });

  test('keeps a restored run the server has not recorded yet', () async {
    final threadKey = (
      serverId: 'test-server',
      roomId: 'room-1',
      threadId: 'thread-1',
    );

    // Simulate a completed run: register a session and complete it.
    final userMessage = TextMessage(
      id: 'user-1',
      user: ChatUser.user,
      createdAt: DateTime(2026, 3, 1),
      text: 'Hello',
      runId: 'run-1',
    );
    final assistantMessage = TextMessage(
      id: 'assistant-1',
      user: ChatUser.assistant,
      createdAt: DateTime(2026, 3, 1),
      text: 'I can help with that',
      runId: 'run-1',
    );
    final conversation = Conversation(
      threadId: 'thread-1',
      messages: [userMessage, assistantMessage],
    );

    final session = _FakeAgentSession();
    registry.register(threadKey, session);
    session.emit(CompletedState(
      threadKey: threadKey,
      runId: 'run-1',
      conversation: conversation,
    ));
    session.complete(AgentSuccess(
      threadKey: threadKey,
      output: 'done',
      runId: 'run-1',
    ));
    await Future<void>.delayed(Duration.zero);

    // The server has not recorded run-1 yet, so its history does not read it.
    api.nextThreadHistory = ThreadHistory(messages: const []);

    // Now create a new ThreadViewState (simulates navigating back).
    final state = ThreadViewState(
      connection: connection,
      auth: auth,
      roomId: 'room-1',
      threadId: 'thread-1',
      registry: registry,
      followRun: neverFollowed,
      contextWindow: Signal<int?>(null),
    );

    // Registry outcome should be applied synchronously.
    final loaded = state.messages.value as MessagesLoaded;
    expect(loaded.messages.length, 2, reason: 'should have both messages');
    expect(loaded.messages.first.id, 'user-1');

    // History replaces only the runs it read, and it read none.
    await Future<void>.delayed(Duration.zero);

    final afterFetch = state.messages.value as MessagesLoaded;
    expect(afterFetch.messages.length, 2,
        reason: 'the fetch must not drop a run history has not recorded');
    expect(afterFetch.messages.first.id, 'user-1');

    state.dispose();
  });

  test('shows a restored client-tool turn once when history read it', () async {
    // The run that waited on the tool records no outcome of its own, live or
    // replayed; history still read it, so what the view held of it goes.
    final threadKey = (
      serverId: 'test-server',
      roomId: 'room-1',
      threadId: 'thread-1',
    );
    final messages = <ChatMessage>[
      TextMessage(
        id: 'user-1',
        user: ChatUser.user,
        createdAt: DateTime(2026, 3, 1),
        text: 'Where am I?',
        runId: 'run-waits',
      ),
      ToolCallMessage.fromExecuted(
        runId: 'run-waits',
        createdAt: null,
        toolCalls: const [
          ToolCallInfo(
            id: 'call-1',
            name: 'locate',
            status: ToolCallStatus.completed,
            result: 'Paris',
          ),
        ],
      ),
      TextMessage(
        id: 'assistant-1',
        user: ChatUser.assistant,
        createdAt: DateTime(2026, 3, 1),
        text: 'You are in Paris',
        runId: 'run-continues',
      ),
    ];
    final session = _FakeAgentSession();
    registry.register(threadKey, session);
    session.emit(CompletedState(
      threadKey: threadKey,
      runId: 'run-continues',
      conversation: Conversation(threadId: 'thread-1', messages: messages),
    ));
    session.complete(AgentSuccess(
      threadKey: threadKey,
      output: 'done',
      runId: 'run-continues',
    ));
    await Future<void>.delayed(Duration.zero);
    api.nextThreadHistory = ThreadHistory(
      messages: messages,
      runOutcomes: {
        'run-continues': NoResponseTile.finished(
          runId: 'run-continues',
          thinkingText: '',
        ),
      },
      runs: [
        const RunEventBundle(runId: 'run-waits', continuesTurn: false),
        const RunEventBundle(runId: 'run-continues', continuesTurn: true),
      ],
    );

    final state = ThreadViewState(
      connection: connection,
      auth: auth,
      roomId: 'room-1',
      threadId: 'thread-1',
      registry: registry,
      followRun: neverFollowed,
      contextWindow: Signal<int?>(null),
    );
    addTearDown(state.dispose);
    await Future<void>.delayed(Duration.zero);

    expect(
      (state.messages.value as MessagesLoaded).messages.map((m) => m.id),
      ['user-1', 'tool-result-run-waits', 'assistant-1'],
    );
  });

  group('a client-tool turn whose history read only the run that waited', () {
    // Opened while a client tool runs: the backend has stored the run that
    // waited, not the one that resumes the turn. Read alone, that run looks
    // like a turn that ended in silence, with its tool's call still pending.
    const threadKey = (
      serverId: 'test-server',
      roomId: 'room-1',
      threadId: 'thread-1',
    );
    const user = TextMessage(
      id: 'user-1',
      user: ChatUser.user,
      createdAt: null,
      text: 'Where am I?',
      runId: 'run-waits',
    );
    const said = TextMessage(
      id: 'said-1',
      user: ChatUser.assistant,
      createdAt: null,
      text: 'Let me look',
      runId: 'run-waits',
    );
    const call = ToolCallInfo(id: 'c1', name: 'search');
    final executed = ToolCallMessage.fromExecuted(
      runId: 'run-waits',
      createdAt: null,
      toolCalls: [
        call.copyWith(status: ToolCallStatus.completed, result: 'Paris'),
      ],
    );
    const reply = TextMessage(
      id: 'reply-1',
      user: ChatUser.assistant,
      createdAt: null,
      text: 'You are in Paris',
      runId: 'run-continues',
    );
    MessageState stateOfTurn(String runId) => MessageState(
          userMessageId: user.id,
          sourceReferences: const [],
          runId: runId,
        );
    late _FakeAgentSession session;
    late _PendingHistoryApi historyApi;
    late ThreadViewState state;
    late List<ChatMessage> beforeTool;
    late ThreadHistory history;

    /// The run that waited as the backend stored it, which replay reads.
    late List<StoredRun> stored;

    /// Leaves the run that waited waiting on its tool, having said [said]
    /// before the call when [speaksFirst].
    Future<void> waitOnTool({bool speaksFirst = false}) async {
      final ext = ExecutionTrackerExtension(logger: testLogger());
      addTearDown(ext.onDispose);
      session = _FakeAgentSession(extensions: [ext]);
      await ext.onAttach(session);
      registry.register(threadKey, session);
      beforeTool = [user, if (speaksFirst) said];
      final waiting = Conversation(
        threadId: 'thread-1',
        messages: beforeTool,
        messageStates: {user.id: stateOfTurn('run-waits')},
      );
      if (speaksFirst) {
        session.emit(RunningState(
          threadKey: threadKey,
          runId: 'run-waits',
          conversation: waiting,
          streaming: TextStreaming(
            messageId: said.id,
            user: ChatUser.assistant,
            text: said.text,
          ),
        ));
      }
      session
        ..emit(RunningState(
          threadKey: threadKey,
          runId: 'run-waits',
          conversation: waiting,
          streaming: const AwaitingText(),
        ))
        ..emitExecution(
          const ServerToolCallStarted(toolCallId: 'c1', toolName: 'search'),
        )
        ..emit(ToolYieldingState(
          threadKey: threadKey,
          runId: 'run-waits',
          conversation: waiting,
          streaming: const AwaitingText(),
          pendingToolCalls: const [call],
          toolDepth: 0,
        ));
      history = ThreadHistory(
        messages: [
          ...beforeTool,
          ToolCallMessage(
            id: 'call-message',
            createdAt: null,
            toolCalls: const [call],
            runId: 'run-waits',
          ),
        ],
        messageStates: {user.id: stateOfTurn('run-waits')},
        runOutcomes: {
          if (!speaksFirst)
            'run-waits': NoResponseTile.finished(
              runId: 'run-waits',
              thinkingText: '',
            ),
        },
        runs: const [
          RunEventBundle(runId: 'run-waits', continuesTurn: false),
        ],
      );
      stored = [
        (
          runId: 'run-waits',
          userMessageId: user.id,
          prompt: user.text,
          events: [
            RunStartedEvent(threadId: 'thread-1', runId: 'run-waits'),
            if (speaksFirst) ...[
              TextMessageStartEvent(messageId: said.id),
              TextMessageContentEvent(messageId: said.id, delta: said.text),
              TextMessageEndEvent(messageId: said.id),
            ],
            const ToolCallStartEvent(
              toolCallId: 'c1',
              toolCallName: 'search',
            ),
            const ToolCallEndEvent(toolCallId: 'c1'),
            const RunFinishedEvent(threadId: 'thread-1', runId: 'run-waits'),
          ],
        ),
      ];
    }

    void openView() {
      historyApi = _PendingHistoryApi();
      state = ThreadViewState(
        connection: _fakeConnection(historyApi),
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      addTearDown(state.dispose);
    }

    Future<void> historyLands() async {
      await historyApi.completeWith(history, stored: stored);
      await Future<void>.delayed(Duration.zero);
    }

    /// The conversation the run resuming the turn carries: the executed
    /// tool, then [withReply].
    Conversation resumed({required bool withReply}) => Conversation(
          threadId: 'thread-1',
          messages: [...beforeTool, executed, if (withReply) reply],
          messageStates: {user.id: stateOfTurn('run-continues')},
        );

    void resume() => session.emit(RunningState(
          threadKey: threadKey,
          runId: 'run-continues',
          conversation: resumed(withReply: false),
          streaming: const AwaitingText(),
        ));

    void complete() => session.emit(CompletedState(
          threadKey: threadKey,
          runId: 'run-continues',
          conversation: resumed(withReply: true),
        ));

    MessagesLoaded loaded() => state.messages.value as MessagesLoaded;

    void expectNoTurnEndedAtTheWait() {
      expect(
        state.executionTrackers.keys,
        isNot(contains(noResponseMessageId('run-waits'))),
      );
      expect(loaded().runOutcomes.keys, isNot(contains('run-waits')));
    }

    test('shows the turn as the session holds it when it lands during the wait',
        () async {
      await waitOnTool();
      openView();
      await historyLands();
      expect(loaded().messages, beforeTool);
      expect(
        state.executionTrackers.keys,
        [noResponseMessageId('run-waits')],
      );
      expect(loaded().runOutcomes, isEmpty);
      final waitingWork =
          state.executionTrackers[noResponseMessageId('run-waits')];
      expect(
        layOutTimeline(
          messages: loaded().messages,
          bands: state.executionTrackers,
          outcomes: loaded().runOutcomes,
          streaming: state.streamingState.value,
          activeRunId: state.activeRunId.value,
        ).tiles.where((tile) => identical(tile.band, waitingWork)),
        hasLength(1),
        reason: 'the work of the turn waiting on its tool has a tile',
      );

      resume();
      expect(loaded().messages, [...beforeTool, executed]);
      expect(
        state.executionTrackers.keys,
        [noResponseMessageId('run-continues')],
      );
      expectNoTurnEndedAtTheWait();
    });

    test('keeps the turn as the session ended it when it lands after',
        () async {
      await waitOnTool();
      openView();
      resume();
      complete();
      await historyLands();

      expect(loaded().messages, [...beforeTool, executed, reply]);
      expect(loaded().messageStates[user.id]?.runId, 'run-continues');
      expect(
        state.executionTrackers.keys,
        [noResponseMessageId('run-continues')],
      );
      expectNoTurnEndedAtTheWait();
    });

    test('keeps the work of what the waiting run said, opened after it ended',
        () async {
      // Opened after the session ended, the view holds no work of the turn,
      // so history's is all there is of what the waiting run said.
      await waitOnTool(speaksFirst: true);
      resume();
      complete();
      session.complete(AgentSuccess(
        threadKey: threadKey,
        output: reply.text,
        runId: 'run-continues',
      ));
      await Future<void>.delayed(Duration.zero);
      openView();
      await historyLands();

      expect(state.executionTrackers.keys, [said.id]);
    });

    test('says how the run ended when the wait was stopped', () async {
      // The stop ends the turn at the run that waited, so history read the
      // whole turn and says how it ended, as it does after a reload.
      await waitOnTool();
      openView();
      session.emit(CancelledState.duringRun(
        threadKey: threadKey,
        runId: 'run-waits',
        conversation: Conversation(threadId: 'thread-1', messages: beforeTool),
      ));
      await historyLands();

      expect(
        loaded().runOutcomes['run-waits'],
        same(history.runOutcomes['run-waits']),
      );
    });
  });

  group('sendMessage', () {
    late AgentRuntimeManager runtimeManager;
    late AgentRuntime runtime;

    setUp(() {
      runtimeManager = AgentRuntimeManager(
        platform: TestPlatformConstraints(),
        toolRegistryResolver: (_) async => const ToolRegistry(),
        logger: testLogger(),
        servers: emptyServers(),
      );
      runtime = runtimeManager.getRuntime(connection);
    });

    tearDown(() async {
      await runtimeManager.dispose();
    });

    test(
        'a send whose cached state still has the reason brings back a '
        'dismissed warning', () async {
      final legacy =
          ThreadHistory(messages: const [], aguiState: _legacyRagState());
      api.nextThreadHistory = legacy;
      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      await Future<void>.delayed(Duration.zero);
      runtime.seedThreadHistory(state.threadKey, legacy);
      state.dismissStateWarnings();

      await state.sendMessage([TextPart('Hello')], runtime);

      expect(state.stateWarnings.value, {ThreadStateWarning.legacyCitations});
      state.dispose();
    });

    test('a send from a disposed view does not throw', () async {
      final legacy =
          ThreadHistory(messages: const [], aguiState: _legacyRagState());
      api.nextThreadHistory = legacy;
      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      await Future<void>.delayed(Duration.zero);
      runtime.seedThreadHistory(state.threadKey, legacy);
      state.dispose();

      await expectLater(
        state.sendMessage([TextPart('Hello')], runtime),
        completes,
      );
    });

    test('a send that lands before the first load keeps its warning', () async {
      api.nextThreadHistory = ThreadHistory(messages: const []);
      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      runtime.seedThreadHistory(
        state.threadKey,
        ThreadHistory(messages: const [], aguiState: _legacyRagState()),
      );

      // Sent before the constructor's history fetch has completed.
      final send = state.sendMessage([TextPart('Hello')], runtime);
      await Future<void>.delayed(Duration.zero);
      await send;

      expect(state.stateWarnings.value, {ThreadStateWarning.legacyCitations});
      state.dispose();
    });

    test(
        'a send does not bring back a warning only an earlier run gave '
        'rise to', () async {
      // A legacy thread that continued: loading warns about the earlier
      // answers, but the state the send carries is clean.
      final continued = ThreadHistory(
        messages: const [],
        aguiState: const {
          'rag': <String, dynamic>{
            'citations': <String>[],
            'citation_index': <String, dynamic>{},
          },
        },
        storedStateWarnings: const {ThreadStateWarning.legacyCitations},
      );
      api.nextThreadHistory = continued;
      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      await Future<void>.delayed(Duration.zero);
      expect(state.stateWarnings.value, {ThreadStateWarning.legacyCitations});
      runtime.seedThreadHistory(state.threadKey, continued);
      state.dismissStateWarnings();

      await state.sendMessage([TextPart('Hello')], runtime);

      expect(state.stateWarnings.value, isEmpty);
      state.dispose();
    });

    test('a spawn that never produced a session leaves nothing counted',
        () async {
      // Nothing will ever report on the send, so the estimate standing in
      // for it has to come back out.
      api.nextThreadHistory = ThreadHistory(messages: const []);

      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      await Future<void>.delayed(Duration.zero);

      // Dispose the runtime so spawn throws.
      await runtimeManager.dispose();
      await state.sendMessage([TextPart('Hello')], runtime);
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(state.contextUsage.usage.value.estimatedTokens, 0);

      state.dispose();
    });

    test('a cancel before the backend names a run leaves nothing counted',
        () async {
      api.nextThreadHistory = ThreadHistory(messages: const []);

      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      await Future<void>.delayed(Duration.zero);

      final future = state.sendMessage([TextPart('Hello')], runtime);
      state.cancelRun();
      await future;
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(state.contextUsage.usage.value.estimatedTokens, 0);

      state.dispose();
    });

    test('run failure without conversation preserves existing messages',
        () async {
      api.nextThreadHistory = ThreadHistory(messages: const []);

      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );

      await Future<void>.delayed(Duration.zero);
      expect(state.messages.value, isA<MessagesLoaded>());

      // Send a message — spawn will succeed but the run will fail
      // (FakeAgUiStreamClient throws). FailedState may have no
      // conversation, so existing messages should be preserved.
      await state.sendMessage([TextPart('Hello')], runtime);

      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // Messages should still be loaded (not replaced with error).
      expect(state.messages.value, isA<MessagesLoaded>());

      state.dispose();
    });

    test('spawn error preserves existing messages', () async {
      final message = TextMessage(
        id: 'msg-1',
        user: ChatUser.user,
        createdAt: DateTime(2026, 3, 1),
        text: 'Existing',
      );
      api.nextThreadHistory = ThreadHistory(messages: [message]);

      // Use a ThreadViewState with no threadId so that sendMessage
      // triggers spawn without a threadId. This forces _resolveThread
      // to call createThread, which we make fail.
      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );

      await Future<void>.delayed(Duration.zero);
      expect(state.messages.value, isA<MessagesLoaded>());

      // Dispose the runtime so spawn throws.
      await runtimeManager.dispose();
      await state.sendMessage([TextPart('Hello')], runtime);

      // Let the error propagate.
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // Messages should still be the original loaded state.
      final status = state.messages.value;
      expect(status, isA<MessagesLoaded>());
      expect((status as MessagesLoaded).messages.length, 1);

      // The error should be surfaced via lastSendError with unsent text.
      final sendError = state.lastSendError.value;
      expect(sendError, isNotNull);
      expect(sendError!.unsentText, 'Hello');

      state.dispose();
    });

    test('consecutive spawn errors each surface lastSendError', () async {
      api.nextThreadHistory = ThreadHistory(messages: const []);

      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );

      await Future<void>.delayed(Duration.zero);
      expect(state.messages.value, isA<MessagesLoaded>());

      // Dispose the runtime so spawn throws.
      await runtimeManager.dispose();

      // First send failure.
      await state.sendMessage([TextPart('First')], runtime);
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(state.lastSendError.value, isNotNull);
      expect(state.lastSendError.value!.unsentText, 'First');

      // Second send failure without manually clearing the error.
      await state.sendMessage([TextPart('Second')], runtime);
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(state.lastSendError.value, isNotNull);
      expect(state.lastSendError.value!.unsentText, 'Second');

      state.dispose();
    });

    test('dispose during sendMessage still registers session in registry',
        () async {
      api.nextThreadHistory = ThreadHistory(messages: const []);

      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );

      await Future<void>.delayed(Duration.zero);
      expect(state.messages.value, isA<MessagesLoaded>());

      // Start sendMessage but dispose before it completes.
      final sendFuture = state.sendMessage([TextPart('Hello')], runtime);
      state.dispose();

      // Let the spawn complete.
      await sendFuture;
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // Session should be tracked in the registry despite disposal.
      final key = (
        serverId: 'test-server',
        roomId: 'room-1',
        threadId: 'thread-1',
      );
      final active = registry.activeSession(key);
      final outcome = registry.completedOutcome(key);
      expect(active != null || outcome != null, isTrue);
    });

    test('dispose does not cancel an active session', () async {
      api.nextThreadHistory = ThreadHistory(messages: const []);

      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );

      await Future<void>.delayed(Duration.zero);

      final fakeSession = _FakeAgentSession();
      state.attachSession(fakeSession);
      expect(state.sessionState.value, isNotNull);

      state.dispose();

      expect(fakeSession.cancelCalled, isFalse);
    });

    test('sessionState is spawning while sendMessage awaits spawn', () async {
      api.nextThreadHistory = ThreadHistory(messages: const []);

      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );

      await Future<void>.delayed(Duration.zero);

      // Start sendMessage without awaiting — observe intermediate state.
      final future = state.sendMessage([TextPart('Hello')], runtime);
      expect(state.sessionState.value, AgentSessionState.spawning);

      await future;
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      state.dispose();
    });

    test('sendMessage is rejected while a session is active', () async {
      api.nextThreadHistory = ThreadHistory(messages: const []);

      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );

      await Future<void>.delayed(Duration.zero);

      // Simulate an active session.
      final fakeSession = _FakeAgentSession();
      state.attachSession(fakeSession);
      expect(state.sessionState.value, isNotNull);

      // Dispose runtime so spawn would throw if called.
      await runtimeManager.dispose();

      // sendMessage should bail out before reaching spawn.
      await state.sendMessage([TextPart('Hello')], runtime);

      // No error means spawn was never attempted.
      expect(state.lastSendError.value, isNull);

      state.dispose();
    });

    test('cancelRun after dispose does not throw', () async {
      // Every other method on this class opens with the disposed guard —
      // `_onAuthChanged` three lines away from `cancelRun` does. Without it
      // the spawn-cancel arm writes `_sessionState`, which `dispose` has
      // already disposed, and signals raise on a write after disposal rather
      // than ignoring it. The throw lands in the Stop button's `onPressed`.
      api.nextThreadHistory = ThreadHistory(messages: const []);

      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );

      await Future<void>.delayed(Duration.zero);

      // Left pending, so the spawn-cancel arm is the one that runs.
      final future = state.sendMessage([TextPart('Hello')], runtime);
      state.dispose();

      state.cancelRun();

      await future;
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    });

    test('cancelRun during spawn prevents session from attaching', () async {
      api.nextThreadHistory = ThreadHistory(messages: const []);

      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );

      await Future<void>.delayed(Duration.zero);

      // Start sendMessage and immediately cancel.
      final future = state.sendMessage([TextPart('Hello')], runtime);
      state.cancelRun();

      await future;
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      // Cancel should have cleaned up — no error from the failed run.
      expect(state.lastSendError.value, isNull);
      expect(state.sessionState.value, isNull);

      state.dispose();
    });

    test('executionTrackers is empty before any streaming', () async {
      api.nextThreadHistory = ThreadHistory(messages: const []);

      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );

      await Future<void>.delayed(Duration.zero);
      expect(state.executionTrackers, isEmpty);

      state.dispose();
    });

    test('session completing clears activeSession and names its run', () async {
      api.nextThreadHistory = ThreadHistory(messages: const []);

      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );

      await Future<void>.delayed(Duration.zero);

      // Attach a fake session and emit CompletedState.
      // This triggers _onRunState → _detachSession → _activeSession = null.
      final fakeSession = _FakeAgentSession();
      state.attachSession(fakeSession);

      final conversation = Conversation(threadId: 'thread-1');
      api.nextRunUsage = RunUsage(
        runId: 'run-1',
        finalInputTokens: 500,
      );
      fakeSession.emit(CompletedState(
        threadKey: (
          serverId: 'test-server',
          roomId: 'room-1',
          threadId: 'thread-1',
        ),
        runId: 'run-1',
        conversation: conversation,
      ));

      // CompletedState triggers _detachSession, which clears sessionState.
      expect(state.sessionState.value, isNull);
      // A completed run is read by its id, so its own record replaces
      // the reading.
      await Future<void>.delayed(Duration.zero);
      expect(state.contextUsage.usage.value.measuredTokens, 500);
      expect(api.runUsageRequests, ['run-1']);

      state.dispose();
    });

    test('live tracker wins over historical on detach absorb', () async {
      const threadKey = (
        serverId: 'test-server',
        roomId: 'room-1',
        threadId: 'thread-1',
      );

      // Seed history so _fetch installs a historical tracker for 'asst-1'.
      api.stored = [
        (
          runId: 'run-prior',
          userMessageId: 'user-prior',
          prompt: 'Q',
          events: [
            RunStartedEvent(threadId: 'thread-1', runId: 'run-prior'),
            const TextMessageStartEvent(messageId: 'asst-1'),
            const TextMessageContentEvent(
              messageId: 'asst-1',
              delta: 'historical',
            ),
            const TextMessageEndEvent(messageId: 'asst-1'),
            RunFinishedEvent(threadId: 'thread-1', runId: 'run-prior'),
          ],
        ),
      ];

      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      await Future<void>.delayed(Duration.zero);

      final historicalTracker = state.executionTrackers['asst-1'];
      expect(historicalTracker, isNotNull,
          reason: 'the replay must seed a band for asst-1');

      // Attach a session whose extension will produce a live tracker under
      // the same message id.
      final ext = ExecutionTrackerExtension(logger: testLogger());
      final fakeSession = _FakeAgentSession(extensions: [ext]);
      await ext.onAttach(fakeSession);
      state.attachSession(fakeSession);

      final conversation = Conversation(threadId: 'thread-1');
      fakeSession.emit(RunningState(
        threadKey: threadKey,
        runId: 'run-live',
        conversation: conversation,
        streaming: const TextStreaming(
          messageId: 'asst-1',
          user: ChatUser.assistant,
          text: 'live',
        ),
      ));

      // The band is keyed by `asst-1` as soon as it speaks, so the two
      // collide from here on.
      final liveTracker = ext.trackers['asst-1'];
      expect(liveTracker, isNotNull);
      expect(identical(liveTracker, historicalTracker), isFalse);

      // Terminal state drives _detachSession → absorb.
      fakeSession.emit(CompletedState(
        threadKey: threadKey,
        runId: 'run-live',
        conversation: conversation,
      ));

      expect(identical(state.executionTrackers['asst-1'], liveTracker), isTrue,
          reason: 'live tracker must overwrite historical on key collision');

      state.dispose();
      ext.onDispose();
    });

    test('executionTrackers are cleaned up on dispose', () async {
      api.nextThreadHistory = ThreadHistory(messages: const []);

      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );

      await Future<void>.delayed(Duration.zero);

      await state.sendMessage([TextPart('Hello')], runtime);

      // Wait for terminal state
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      state.dispose();
      expect(state.executionTrackers, isEmpty);
    });

    group('runs ended', () {
      Conversation asked(List<String> texts) => texts.fold(
            Conversation.empty(threadId: 'thread-1'),
            (conversation, text) => appendUserMessage(
              conversation,
              TextMessage.create(
                  id: 'u-$text', user: ChatUser.user, text: text),
            ),
          );
      final key = (
        serverId: 'test-server',
        roomId: 'room-1',
        threadId: 'thread-1',
      );

      ThreadViewState build() {
        api.nextThreadHistory = ThreadHistory(messages: const []);
        return ThreadViewState(
          connection: connection,
          auth: auth,
          roomId: 'room-1',
          threadId: 'thread-1',
          registry: registry,
          followRun: neverFollowed,
          contextWindow: Signal<int?>(null),
        );
      }

      Future<ThreadViewState> open() async {
        final state = build();
        addTearDown(state.dispose);
        await Future<void>.delayed(Duration.zero);
        return state;
      }

      test('a completed, a failed, and a cancelled run each count once',
          () async {
        final state = await open();
        expect(state.runsEnded.value, 0);

        final completed = _FakeAgentSession();
        state.attachSession(completed);
        completed.emit(CompletedState(
          threadKey: key,
          runId: 'run-1',
          conversation: asked(['one']),
        ));
        expect(state.runsEnded.value, 1);

        final failed = _FakeAgentSession();
        state.attachSession(failed);
        failed.emit(FailedState.duringRun(
          threadKey: key,
          runId: 'run-2',
          // Not logged as an error, so the test output stays clean.
          reason: FailureReason.networkLost,
          error: 'connection lost',
          conversation: asked(['two']),
        ));
        expect(state.runsEnded.value, 2);

        final cancelled = _FakeAgentSession();
        state.attachSession(cancelled);
        cancelled.emit(CancelledState.duringRun(
          threadKey: key,
          runId: 'run-3',
          conversation: asked(['three']),
        ));
        expect(state.runsEnded.value, 3);
      });

      test('a running run does not count', () async {
        final state = await open();
        final session = _FakeAgentSession();
        state.attachSession(session);

        session.emit(RunningState(
          threadKey: key,
          runId: 'run-1',
          conversation: asked(['one']),
          streaming: const AwaitingText(),
        ));

        expect(state.runsEnded.value, 0);
      });

      test('disposing the view mid-run does not count', () {
        // Leaving a thread disposes its view while the run goes on in the
        // background; that is not the run ending. Built by hand rather than
        // with open(), whose tearDown would dispose it a second time.
        final state = build();
        final session = _FakeAgentSession();
        state.attachSession(session);
        session.emit(RunningState(
          threadKey: key,
          runId: 'run-1',
          conversation: asked(['one']),
          streaming: const AwaitingText(),
        ));
        expect(state.activeRunId.value, 'run-1');
        var ended = 0;
        // subscribe fires once with the current value; count only what follows.
        final unsubscribe = state.runsEnded.subscribe((_) => ended++);
        addTearDown(unsubscribe);
        ended = 0;

        state.dispose();

        expect(ended, 0);
      });
    });

    group('context reading', () {
      RunUsage measuredRun(String runId, int tokens) => RunUsage(
            runId: runId,
            finalInputTokens: tokens,
          );
      Conversation asked(List<String> texts) => texts.fold(
            Conversation.empty(threadId: 'thread-1'),
            (conversation, text) => appendUserMessage(
              conversation,
              TextMessage.create(
                  id: 'u-$text', user: ChatUser.user, text: text),
            ),
          );
      final key = (
        serverId: 'test-server',
        roomId: 'room-1',
        threadId: 'thread-1',
      );

      Future<ThreadViewState> open({int measured = 1000}) async {
        api.nextThreadHistory = ThreadHistory(
          messages: const [],
          latestMeasurement: MeasuredRun(
            usage: measuredRun('run-1', measured),
            coveredMessages: 0,
          ),
        );
        final state = ThreadViewState(
          connection: connection,
          auth: auth,
          roomId: 'room-1',
          threadId: 'thread-1',
          registry: registry,
          followRun: neverFollowed,
          contextWindow: Signal<int?>(8192),
        );
        addTearDown(state.dispose);
        await Future<void>.delayed(Duration.zero);
        return state;
      }

      test('is seeded by the loaded history', () async {
        final state = await open(measured: 1800);

        expect(state.contextUsage.usage.value.tokens, 1800);
        expect(state.contextUsage.usage.value.contextWindow, 8192);
      });

      test('a send counts its message', () async {
        // Every send counts, suggestion taps included, because the count
        // starts in the send and not in the composer.
        final state = await open();
        await runtimeManager.dispose();

        final sending = state.sendMessage([TextPart('a suggestion')], runtime);

        expect(state.contextUsage.usage.value.estimatedTokens,
            estimateDraftTokens('a suggestion'));
        await sending;
      });

      test('a send refused because a run is active counts nothing', () async {
        // The view turns this send away, so the next request never carries
        // it.
        final state = await open();
        state.attachSession(_FakeAgentSession());
        expect(state.sessionState.value, isNotNull,
            reason: 'precondition: a session is attached');

        await state.sendMessage([TextPart('refused')], runtime);

        expect(state.contextUsage.usage.value.estimatedTokens, 0);
      });

      test('grows with its run in progress', () async {
        final state = await open();
        final session = _FakeAgentSession();
        state.attachSession(session);

        RunningState running(Conversation conversation) => RunningState(
              threadKey: key,
              runId: 'run-2',
              conversation: conversation,
              streaming: const AwaitingText(),
            );
        session.emit(running(asked(['q'])));
        session.emit(running(asked(['q', 'more'])));

        expect(
          state.contextUsage.usage.value.estimatedTokens,
          estimateTranscriptTokens(asked(['q', 'more']).transcript.messages),
        );
        expect(state.contextUsage.usage.value.measuredTokens, 1000);
      });

      test('a run that errored keeps what it carried counted', () async {
        // An errored run keeps what it streamed, and the next request
        // carries it; a failed run is not read for a count, so the
        // measurement stays where it was.
        final state = await open();
        final session = _FakeAgentSession();
        state.attachSession(session);
        api.nextRunUsage = measuredRun('run-2', 5000);

        session.emit(FailedState.duringRun(
          threadKey: key,
          runId: 'run-2',
          // A reason the view does not log as an error, so the test
          // output stays clean; the reading treats every failure alike.
          reason: FailureReason.networkLost,
          error: 'connection lost',
          conversation: asked(['what was asked']),
        ));

        expect(
          state.contextUsage.usage.value.estimatedTokens,
          estimateTranscriptTokens(
              asked(['what was asked']).transcript.messages),
        );
        await Future<void>.delayed(Duration.zero);
        expect(state.contextUsage.usage.value.measuredTokens, 1000);
      });

      test('a stopped run keeps its message counted', () async {
        // A stopped run keeps its message, and the next request carries it.
        final state = await open();
        final session = _FakeAgentSession();
        state.attachSession(session);

        session.emit(CancelledState.duringRun(
          threadKey: key,
          runId: 'run-2',
          conversation: asked(['what was asked']),
        ));

        expect(
          state.contextUsage.usage.value.estimatedTokens,
          estimateTranscriptTokens(
              asked(['what was asked']).transcript.messages),
        );
        expect(state.contextUsage.usage.value.measuredTokens, 1000);
      });

      // Registers a session, drives it to its outcome, and waits one tick so
      // the registry files that outcome; the view then restores it instead of
      // attaching to a live session.
      Future<ThreadViewState> restored(
        void Function(ManualAgentSession session) finish,
      ) async {
        final session = ManualAgentSession(key);
        registry.register(key, session);
        finish(session);
        await Future<void>.delayed(Duration.zero);
        final state = ThreadViewState(
          connection: connection,
          auth: auth,
          roomId: 'room-1',
          threadId: 'thread-1',
          registry: registry,
          followRun: neverFollowed,
          contextWindow: Signal<int?>(8192),
        );
        addTearDown(state.dispose);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        return state;
      }

      ThreadHistory measuredAt1000() => ThreadHistory(
            messages: const [],
            latestMeasurement: MeasuredRun(
              usage: measuredRun('run-1', 1000),
              coveredMessages: 0,
            ),
          );

      test('reads a run restored from the registry by its id', () async {
        api
          ..nextThreadHistory = ThreadHistory(messages: const [])
          ..nextRunUsage = measuredRun('run-restored', 2400);

        final state = await restored(
          (session) => session.completeAsCompleted(
            runId: 'run-restored',
            conversation: asked(['restored']),
          ),
        );

        expect(state.contextUsage.usage.value.measuredTokens, 2400);
        expect(state.contextUsage.usage.value.isExact, isTrue);
        expect(api.runUsageRequests, ['run-restored']);
      });

      test('a restored failed run keeps what it carried, unread', () async {
        api
          ..nextThreadHistory = measuredAt1000()
          ..nextRunUsage = measuredRun('run-restored', 5000);

        final state = await restored((session) {
          session.emit(FailedState.duringRun(
            threadKey: key,
            runId: 'run-restored',
            reason: FailureReason.networkLost,
            error: 'connection lost',
            conversation: asked(['restored']),
          ));
          session.completeWithoutTransition();
        });

        expect(state.contextUsage.usage.value.measuredTokens, 1000);
        expect(
          state.contextUsage.usage.value.estimatedTokens,
          estimateTranscriptTokens(asked(['restored']).transcript.messages),
        );
      });

      test('a restored cancelled run keeps what it carried, unread', () async {
        api
          ..nextThreadHistory = measuredAt1000()
          ..nextRunUsage = measuredRun('run-restored', 5000);

        final state = await restored((session) {
          session.emit(CancelledState.duringRun(
            threadKey: key,
            runId: 'run-restored',
            conversation: asked(['restored']),
          ));
          session.completeWithoutTransition();
        });

        expect(state.contextUsage.usage.value.measuredTokens, 1000);
        expect(
          state.contextUsage.usage.value.estimatedTokens,
          estimateTranscriptTokens(asked(['restored']).transcript.messages),
        );
      });
    });
  });

  group('approval surface', () {
    test('pendingApproval is null when no session is attached', () async {
      api.nextThreadHistory = ThreadHistory(messages: const []);
      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      await Future<void>.delayed(Duration.zero);

      expect(state.pendingApproval.value, isNull);

      state.dispose();
    });

    test('respondToApproval is a silent no-op when no session', () async {
      api.nextThreadHistory = ThreadHistory(messages: const []);
      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      await Future<void>.delayed(Duration.zero);

      final stale = ApprovalRequest(
        toolCallId: 'tc-x',
        toolName: 't',
        arguments: const {},
        rationale: 'r',
      );
      expect(() => state.respondToApproval(stale, true), returnsNormally);

      state.dispose();
    });

    test(
      'pendingApproval reflects active session\'s approval extension state',
      () async {
        final approval = HumanApprovalExtension();
        final session = _FakeAgentSession(extensions: [approval]);
        api.nextThreadHistory = ThreadHistory(messages: const []);
        final state = ThreadViewState(
          connection: connection,
          auth: auth,
          roomId: 'room-1',
          threadId: 'thread-1',
          registry: registry,
          followRun: neverFollowed,
          contextWindow: Signal<int?>(null),
        );
        await Future<void>.delayed(Duration.zero);

        state.attachSession(session);

        final future = approval.requestApproval(
          toolCallId: 'tc-1',
          toolName: 'send_email',
          arguments: const {'to': 'a@b.c'},
          rationale: 'send a message',
        );

        final pending = state.pendingApproval.value;
        expect(pending, isNotNull);
        expect(pending!.toolCallId, 'tc-1');

        state.respondToApproval(pending, true);
        expect(await future, isTrue);
        expect(state.pendingApproval.value, isNull);

        state.dispose();
      },
    );

    test(
      'pendingApproval re-evaluates when active session is swapped',
      () async {
        final approvalA = HumanApprovalExtension();
        final approvalB = HumanApprovalExtension();
        final sessionA = _FakeAgentSession(extensions: [approvalA]);
        final sessionB = _FakeAgentSession(extensions: [approvalB]);
        api.nextThreadHistory = ThreadHistory(messages: const []);
        final state = ThreadViewState(
          connection: connection,
          auth: auth,
          roomId: 'room-1',
          threadId: 'thread-1',
          registry: registry,
          followRun: neverFollowed,
          contextWindow: Signal<int?>(null),
        );
        await Future<void>.delayed(Duration.zero);

        state.attachSession(sessionA);
        expect(state.pendingApproval.value, isNull);

        // Swap to a new session whose extension already has a pending
        // request. The Computed must re-read from the newly active
        // session's extension, not the old one.
        approvalB.requestApproval(
          toolCallId: 'tc-B',
          toolName: 't',
          arguments: const {},
          rationale: 'r',
        );
        state.attachSession(sessionB);

        expect(state.pendingApproval.value, isNotNull);
        expect(state.pendingApproval.value!.toolCallId, 'tc-B');

        state.dispose();
      },
    );
  });

  group('reconnect status', () {
    test('a run stopped mid-run is not read by its id', () async {
      // A cut-off run's count is never read: the backend finishes the run
      // and records more than the transcript kept.
      api.nextThreadHistory = ThreadHistory(messages: const []);

      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      await Future<void>.delayed(Duration.zero);

      final session = _FakeAgentSession();
      state.attachSession(session);
      api.nextRunUsage = RunUsage(
        runId: 'run-7',
        finalInputTokens: 700,
      );
      session.emit(
        CancelledState.duringRun(
          threadKey: (
            serverId: 'test-server',
            roomId: 'room-1',
            threadId: 'thread-1',
          ),
          runId: 'run-7',
        ),
      );

      await Future<void>.delayed(Duration.zero);
      expect(state.contextUsage.usage.value.measuredTokens, isNull);

      state.dispose();
    });

    test('a run that failed before it was named leaves nothing counted',
        () async {
      // The run never reached the backend, so no usage will ever be
      // recorded for it and no id can be fetched by.
      api.nextThreadHistory = ThreadHistory(messages: const []);

      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      await Future<void>.delayed(Duration.zero);

      final session = _FakeAgentSession();
      state.contextUsage.sendStarted([TextPart('Hello')]);
      expect(state.contextUsage.usage.value.estimatedTokens, greaterThan(0));
      state.attachSession(session);
      session.emit(
        FailedState.preRun(
          threadKey: (
            serverId: 'test-server',
            roomId: 'room-1',
            threadId: 'thread-1',
          ),
          reason: FailureReason.internalError,
          error: 'spawn refused',
        ),
      );

      expect(state.contextUsage.usage.value.estimatedTokens, 0);

      state.dispose();
    });

    test(
      'FailedState with streamResumeFailed reason maps to friendly '
      'SendError copy',
      () async {
        api.nextThreadHistory = ThreadHistory(messages: const []);

        final state = ThreadViewState(
          connection: connection,
          auth: auth,
          roomId: 'room-1',
          threadId: 'thread-1',
          registry: registry,
          followRun: neverFollowed,
          contextWindow: Signal<int?>(null),
        );
        await Future<void>.delayed(Duration.zero);

        final session = _FakeAgentSession();
        state.attachSession(session);

        session.emit(
          FailedState.preRun(
            threadKey: (
              serverId: 'test-server',
              roomId: 'room-1',
              threadId: 'thread-1',
            ),
            reason: FailureReason.streamResumeFailed,
            error: '$streamResumeFailedPrefix NetworkException: server gone',
          ),
        );

        final sendError = state.lastSendError.value;
        expect(sendError, isNotNull);
        expect(sendError!.error, contains('Connection lost'));
        expect(sendError.error, contains('send your message again'));

        state.dispose();
      },
    );

    test(
      'FailedState without the marker prefix passes the raw error through',
      () async {
        api.nextThreadHistory = ThreadHistory(messages: const []);

        final state = ThreadViewState(
          connection: connection,
          auth: auth,
          roomId: 'room-1',
          threadId: 'thread-1',
          registry: registry,
          followRun: neverFollowed,
          contextWindow: Signal<int?>(null),
        );
        await Future<void>.delayed(Duration.zero);

        final session = _FakeAgentSession();
        state.attachSession(session);

        session.emit(
          FailedState.preRun(
            threadKey: (
              serverId: 'test-server',
              roomId: 'room-1',
              threadId: 'thread-1',
            ),
            reason: FailureReason.serverError,
            error: 'Some other failure',
          ),
        );

        expect(state.lastSendError.value?.error, 'Some other failure');

        state.dispose();
      },
    );

    test('a failure whose text is blank says it gave no reason', () async {
      api.nextThreadHistory = ThreadHistory(messages: const []);

      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      await Future<void>.delayed(Duration.zero);

      for (final blank in ['', ' \n ']) {
        state.clearSendError();
        final session = _FakeAgentSession();
        state.attachSession(session);
        session.emit(
          FailedState.preRun(
            threadKey: (
              serverId: 'test-server',
              roomId: 'room-1',
              threadId: 'thread-1',
            ),
            reason: FailureReason.serverError,
            error: blank,
          ),
        );

        expect(
          state.lastSendError.value?.error,
          'The run failed without giving a reason.',
          reason: 'error of ${blank.length} blank character(s)',
        );
      }

      state.dispose();
    });

    test(
      'a failed run is logged by its reason and run, never by the error text '
      'the backend sent',
      () async {
        api.nextThreadHistory = ThreadHistory(messages: const []);
        final sink = MemorySink();
        LogManager.instance.addSink(sink);
        addTearDown(() => LogManager.instance.removeSink(sink));

        final state = ThreadViewState(
          connection: connection,
          auth: auth,
          roomId: 'room-1',
          threadId: 'thread-1',
          registry: registry,
          followRun: neverFollowed,
          contextWindow: Signal<int?>(null),
        );
        addTearDown(state.dispose);
        await Future<void>.delayed(Duration.zero);

        final session = _FakeAgentSession();
        state.attachSession(session);

        session.emit(
          const FailedState.duringRun(
            threadKey: (
              serverId: 'test-server',
              roomId: 'room-1',
              threadId: 'thread-1',
            ),
            runId: 'run-1',
            reason: FailureReason.serverError,
            error: 'backend-supplied detail',
          ),
        );

        final record = sink.records.singleWhere(
          (r) => r.message.startsWith('Thread run failed'),
        );
        expect(record.toString(), isNot(contains('backend-supplied detail')));
        expect(record.attributes, containsPair('runId', 'run-1'));
      },
    );

    test(
      'auth flip to ExpiredSession cancels an in-flight history fetch',
      () async {
        final pendingApi = _PendingHistoryApi();
        final pendingConnection = _fakeConnection(pendingApi);
        auth.login(
          provider: const OidcProvider(
            discoveryUrl: 'https://sso/.well-known/openid-configuration',
            clientId: 'c',
          ),
          tokens: AuthTokens(
            accessToken: 'a',
            refreshToken: 'r',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );

        final state = ThreadViewState(
          connection: pendingConnection,
          auth: auth,
          roomId: 'room-1',
          threadId: 'thread-1',
          registry: registry,
          followRun: neverFollowed,
          contextWindow: Signal<int?>(null),
        );
        await Future<void>.delayed(Duration.zero);

        final inFlightToken = pendingApi.capturedToken;
        expect(inFlightToken, isNotNull);
        expect(inFlightToken!.isCancelled, isFalse);

        auth.markSessionExpired();

        expect(inFlightToken.isCancelled, isTrue);
        expect(inFlightToken.reason, 'auth expired');

        pendingApi.completeWith(ThreadHistory(messages: const []));
        await Future<void>.delayed(Duration.zero);

        state.dispose();
      },
    );

    test(
      'auth flip to ExpiredSession cancels the active AgentSession',
      () async {
        api.nextThreadHistory = ThreadHistory(messages: const []);
        auth.login(
          provider: const OidcProvider(
            discoveryUrl: 'https://sso/.well-known/openid-configuration',
            clientId: 'c',
          ),
          tokens: AuthTokens(
            accessToken: 'a',
            refreshToken: 'r',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );

        final state = ThreadViewState(
          connection: connection,
          auth: auth,
          roomId: 'room-1',
          threadId: 'thread-1',
          registry: registry,
          followRun: neverFollowed,
          contextWindow: Signal<int?>(null),
        );
        await Future<void>.delayed(Duration.zero);

        final session = _FakeAgentSession();
        state.attachSession(session);
        expect(session.cancelCalled, isFalse);

        // A 401 on an unrelated surface flips the session.
        auth.markSessionExpired();

        expect(session.cancelCalled, isTrue);

        state.dispose();
      },
    );

    test(
      'spawn-time AuthException persists composer text for the auth roundtrip',
      () async {
        // Drives the full path: a runtime that throws AuthException at
        // spawn time → SessionSpawner funnels via markSessionExpired →
        // ThreadViewState's onAuthExpired callback persists the prompt
        // to ReturnToStorage so the composer survives the route guard
        // redirect and reload.
        api.nextThreadHistory = ThreadHistory(messages: const []);
        auth.login(
          provider: const OidcProvider(
            discoveryUrl: 'https://sso/.well-known/openid-configuration',
            clientId: 'c',
          ),
          tokens: AuthTokens(
            accessToken: testJwt({'iss': 'iss-test', 'sub': 'user'}),
            refreshToken: 'r',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );

        final state = ThreadViewState(
          connection: connection,
          auth: auth,
          roomId: 'room-1',
          threadId: 'thread-1',
          registry: registry,
          followRun: neverFollowed,
          contextWindow: Signal<int?>(null),
        );
        await Future<void>.delayed(Duration.zero);

        final throwingRuntime = _AuthExceptionThrowingRuntime(connection);
        await state.sendMessage([
          const TextPart('half-written question'),
          ImagePart(bytes: Uint8List.fromList([0x89]), mimeType: 'image/png'),
        ], throwingRuntime);

        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(Duration.zero);
        }

        final restored = await ReturnToStorage.loadComposer(
          serverId: 'test-server',
          userId: _testUserId,
          roomId: 'room-1',
        );
        expect(
          restored,
          'half-written question$composerDraftImageMarker',
          reason: 'ThreadViewState must wire composer persistence as the '
              "spawner's onAuthExpired hook; without it the user's draft "
              'is dropped on the floor by the redirect. Storage holds a '
              "string, so the draft keeps the image's position and not its "
              'bytes.',
        );

        state.dispose();
      },
    );

    test('FailedState(authExpired) funnels through markSessionExpired',
        () async {
      api.nextThreadHistory = ThreadHistory(messages: const []);
      auth.login(
        provider: const OidcProvider(
          discoveryUrl: 'https://sso/.well-known/openid-configuration',
          clientId: 'c',
        ),
        tokens: AuthTokens(
          accessToken: 'a',
          refreshToken: 'r',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );

      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      await Future<void>.delayed(Duration.zero);

      final session = _FakeAgentSession();
      state.attachSession(session);

      session.emit(
        FailedState.preRun(
          threadKey: (
            serverId: 'test-server',
            roomId: 'room-1',
            threadId: 'thread-1',
          ),
          reason: FailureReason.authExpired,
          error: 'Session expired',
        ),
      );

      expect(auth.session.value, isA<ExpiredSession>());
      expect(state.lastSendError.value?.error, 'Session expired');

      state.dispose();
    });

    test('mirrors session.reconnectStatus into reconnectStatus signal',
        () async {
      api.nextThreadHistory = ThreadHistory(messages: const []);

      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      await Future<void>.delayed(Duration.zero);

      final session = _FakeAgentSession();
      state.attachSession(session);
      expect(state.reconnectStatus.value, isNull);

      session.emitReconnect(
        const Reconnecting(attempt: 1, lastEventId: 'r:0'),
      );
      expect(state.reconnectStatus.value, isA<Reconnecting>());

      session.emitReconnect(const Reconnected(attempt: 1));
      expect(state.reconnectStatus.value, isA<Reconnected>());

      state.dispose();
    });

    test(
      'attaching a new session clears non-Reconnected mirrored state',
      () async {
        // Only `Reconnected` survives `_detachSession` (so its 4s
        // auto-dismiss timer can run). Other states clear so a stale
        // in-flight banner does not linger across sessions.
        api.nextThreadHistory = ThreadHistory(messages: const []);

        final state = ThreadViewState(
          connection: connection,
          auth: auth,
          roomId: 'room-1',
          threadId: 'thread-1',
          registry: registry,
          followRun: neverFollowed,
          contextWindow: Signal<int?>(null),
        );
        await Future<void>.delayed(Duration.zero);

        final sessionA = _FakeAgentSession();
        state.attachSession(sessionA);
        sessionA.emitReconnect(const Reconnecting(attempt: 1));
        expect(state.reconnectStatus.value, isA<Reconnecting>());

        // Detach + attach a new session: Reconnecting must clear since
        // its presence would imply a stale in-flight banner.
        final sessionB = _FakeAgentSession();
        state.attachSession(sessionB);
        expect(state.reconnectStatus.value, isNull);

        state.dispose();
      },
    );

    test(
      'detach preserves Reconnected so the auto-dismiss timer can run',
      () async {
        api.nextThreadHistory = ThreadHistory(messages: const []);

        final state = ThreadViewState(
          connection: connection,
          auth: auth,
          roomId: 'room-1',
          threadId: 'thread-1',
          registry: registry,
          followRun: neverFollowed,
          contextWindow: Signal<int?>(null),
        );
        await Future<void>.delayed(Duration.zero);

        final session = _FakeAgentSession();
        state.attachSession(session);
        session.emitReconnect(const Reconnected(attempt: 1));
        expect(state.reconnectStatus.value, isA<Reconnected>());

        // Detach via a terminal CompletedState. Reconnected must survive
        // so the banner widget's 4s auto-dismiss timer can complete.
        session.emit(
          CompletedState(
            threadKey: (
              serverId: 'test-server',
              roomId: 'room-1',
              threadId: 'thread-1',
            ),
            runId: 'run-1',
            conversation: const Conversation(
              threadId: 'thread-1',
              messages: [],
            ),
          ),
        );
        expect(state.reconnectStatus.value, isA<Reconnected>());

        state.dispose();
      },
    );
  });

  group('isCancellable', () {
    test('false during the post-attach IdleState window', () async {
      // Session is attached but the orchestrator hasn't emitted
      // RunningState yet. Without this gate, the Stop button would
      // be enabled but `cancelRun` is a silent no-op in this window.
      api.nextThreadHistory = ThreadHistory(messages: const []);
      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      await Future<void>.delayed(Duration.zero);

      final session = _FakeAgentSession();
      state.attachSession(session);
      // Session attached, runState defaults to IdleState.
      expect(state.isCancellable.value, isFalse);

      state.dispose();
    });

    test('true once the orchestrator emits RunningState', () async {
      // Pins the positive side of the gate. Without this, regressing
      // the `RunningState` arm to always return false would silently
      // disable the Stop button for normal runs and pass the IdleState
      // test above.
      api.nextThreadHistory = ThreadHistory(messages: const []);
      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      await Future<void>.delayed(Duration.zero);

      final session = _FakeAgentSession();
      state.attachSession(session);
      session.emit(
        RunningState(
          threadKey: (
            serverId: 'test-server',
            roomId: 'room-1',
            threadId: 'thread-1',
          ),
          runId: 'run-1',
          conversation: const Conversation(
            threadId: 'thread-1',
            messages: [],
          ),
          streaming: const AwaitingText(),
        ),
      );
      expect(state.isCancellable.value, isTrue);

      state.dispose();
    });

    test('true while in ToolYieldingState', () async {
      // Independent of the RunningState case: the orchestrator's
      // `cancelRun` `ToolYieldingState` arm cancels the in-flight
      // `_resumeStream → startRun` await, and the UI gate must
      // expose that capability.
      api.nextThreadHistory = ThreadHistory(messages: const []);
      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      await Future<void>.delayed(Duration.zero);

      final session = _FakeAgentSession();
      state.attachSession(session);
      session.emit(
        ToolYieldingState(
          threadKey: (
            serverId: 'test-server',
            roomId: 'room-1',
            threadId: 'thread-1',
          ),
          runId: 'run-1',
          conversation: const Conversation(
            threadId: 'thread-1',
            messages: [],
          ),
          streaming: const AwaitingText(),
          pendingToolCalls: const [],
          toolDepth: 0,
        ),
      );
      expect(state.isCancellable.value, isTrue);

      state.dispose();
    });
  });

  group('history fetch auth funneling', () {
    void activate(AuthSession a) {
      a.login(
        provider: const OidcProvider(
          discoveryUrl: 'https://sso/.well-known/openid-configuration',
          clientId: 'c',
        ),
        tokens: AuthTokens(
          accessToken: 'a',
          refreshToken: 'r',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
    }

    test('AuthException funnels through markSessionExpired', () async {
      activate(auth);
      api.nextThreadHistoryError = AuthException(
        statusCode: 401,
        message: 'JWT validation failed',
      );

      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );

      await Future<void>.delayed(Duration.zero);

      expect(
        auth.session.value,
        isA<ExpiredSession>(),
        reason: 'AuthException must flip the session to ExpiredSession so the '
            'route guard can redirect.',
      );
      expect(
        state.messages.value,
        isA<MessagesLoading>(),
        reason: 'On AuthException we leave MessagesLoading rather than '
            'flashing MessagesFailed before the redirect.',
      );

      state.dispose();
    });

    test('PermissionDeniedException surfaces as MessagesFailed', () async {
      activate(auth);
      api.nextThreadHistoryError = PermissionDeniedException(
        statusCode: 403,
        message: 'Forbidden',
      );

      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );

      await Future<void>.delayed(Duration.zero);

      expect(auth.session.value, isA<ActiveSession>());
      expect(state.messages.value, isA<MessagesFailed>());

      state.dispose();
    });

    test('generic error still produces MessagesFailed (regression)', () async {
      activate(auth);
      api.nextThreadHistoryError = Exception('network down');

      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );

      await Future<void>.delayed(Duration.zero);

      expect(auth.session.value, isA<ActiveSession>());
      expect(state.messages.value, isA<MessagesFailed>());

      state.dispose();
    });
  });

  group('submitFeedback auth funneling', () {
    void activate(AuthSession a) {
      a.login(
        provider: const OidcProvider(
          discoveryUrl: 'https://sso/.well-known/openid-configuration',
          clientId: 'c',
        ),
        tokens: AuthTokens(
          accessToken: 'a',
          refreshToken: 'r',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
    }

    test('AuthException funnels through markSessionExpired', () async {
      activate(auth);
      api.nextThreadHistory = ThreadHistory(messages: const []);
      api.nextSubmitFeedbackError = AuthException(
        statusCode: 401,
        message: 'JWT validation failed',
      );

      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      await Future<void>.delayed(Duration.zero);

      state.submitFeedback('run-1', FeedbackType.thumbsUp, null);
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(auth.session.value, isA<ExpiredSession>());

      state.dispose();
    });
  });

  group('feedback outcomes', () {
    void activate(AuthSession a) {
      a.login(
        provider: const OidcProvider(
          discoveryUrl: 'https://sso/.well-known/openid-configuration',
          clientId: 'c',
        ),
        tokens: AuthTokens(
          accessToken: 'a',
          refreshToken: 'r',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
    }

    Future<ThreadViewState> open() async {
      api.nextThreadHistory = ThreadHistory(messages: const []);
      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      await Future<void>.delayed(Duration.zero);
      addTearDown(state.dispose);
      return state;
    }

    test('submitFeedback reports that the record landed', () async {
      final state = await open();

      expect(
        await state.submitFeedback('run-1', FeedbackType.thumbsDown, 'why'),
        isTrue,
      );
      expect(api.submittedFeedback.single.reason, 'why');
    });

    test('submitFeedback reports a rejected record instead of throwing',
        () async {
      api.nextSubmitFeedbackError = const NetworkException(message: 'offline');
      final state = await open();

      expect(
        await state.submitFeedback('run-1', FeedbackType.thumbsDown, 'why'),
        isFalse,
      );
    });

    test('fetchRunFeedback answers the reason on file', () async {
      api.nextRunFeedback = const RunFeedback(reason: 'boom');
      final state = await open();

      expect(await state.fetchRunFeedback('run-1'), 'boom');
      expect(
        api.requestedRunFeedback.single,
        (roomId: 'room-1', threadId: 'thread-1', runId: 'run-1'),
      );
    });

    test('fetchRunFeedback answers null when no record is on file', () async {
      final state = await open();

      expect(await state.fetchRunFeedback('run-1'), isNull);
    });

    test('fetchRunFeedback expires the session on a dead grant', () async {
      // Its sibling submitFeedback funnels a 401; without the same funnel
      // here, a user who reads "couldn't check" and cancels is left on a
      // signed-in screen with a dead grant.
      activate(auth);
      api.nextRunFeedbackError =
          const AuthException(message: 'expired', statusCode: 401);
      final state = await open();

      await expectLater(
        state.fetchRunFeedback('run-1'),
        throwsA(isA<AuthException>()),
      );

      expect(auth.session.value, isA<ExpiredSession>());
    });

    test('fetchRunFeedback rethrows so the dialog can say it could not read',
        () async {
      // Swallowing this would let the dialog show an unread note as an absent
      // one, and the write is an upsert.
      api.nextRunFeedbackError = const NetworkException(message: 'offline');
      final state = await open();

      expect(
        () => state.fetchRunFeedback('run-1'),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  group('run outcomes reaching the view', () {
    NoResponseTile parked(String run) => NoResponseTile.cancelled(
          runId: run,
          thinkingText: 'weighing it',
        );

    test('a refresh shows how the backend finished a run the user stopped',
        () async {
      // Stop closes the connection and the backend completes the run anyway,
      // so the stored run carries the answer the user did not wait for. What
      // the view held for it — a stopped tile and part of the work — is only
      // what it saw before it looked away.
      const key = (
        serverId: 'test-server',
        roomId: 'room-1',
        threadId: 'thread-1',
      );
      api.nextThreadHistory = ThreadHistory(messages: const []);
      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      addTearDown(state.dispose);
      await Future<void>.delayed(Duration.zero);

      final ext = ExecutionTrackerExtension(logger: testLogger());
      addTearDown(ext.onDispose);
      final session = _FakeAgentSession(extensions: [ext]);
      await ext.onAttach(session);
      registry.register(key, session);
      state.attachSession(session);
      session.emit(
        RunningState(
          threadKey: key,
          runId: 'run-0',
          conversation: Conversation(threadId: 'thread-1'),
          streaming: const AwaitingText(),
        ),
      );
      session.emitExecution(
        const ServerToolCallStarted(toolCallId: 'c1', toolName: 'search'),
      );
      session.emit(
        CancelledState.duringRun(
          threadKey: key,
          runId: 'run-0',
          conversation: Conversation(
            threadId: 'thread-1',
            runOutcomes: {'run-0': parked('run-0')},
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      api.stored = [
        (
          runId: 'run-0',
          userMessageId: 'u0',
          prompt: 'ask',
          events: [
            RunStartedEvent(threadId: 'thread-1', runId: 'run-0'),
            const TextMessageStartEvent(messageId: 'm1'),
            const TextMessageContentEvent(
              messageId: 'm1',
              delta: 'Found it.',
            ),
            const TextMessageEndEvent(messageId: 'm1'),
            const ToolCallStartEvent(
              toolCallId: 'c1',
              toolCallName: 'search',
              parentMessageId: 'm1',
            ),
            const ToolCallEndEvent(toolCallId: 'c1'),
            const ToolCallResultEvent(
              messageId: 'tr-c1',
              toolCallId: 'c1',
              content: 'ok',
            ),
            RunFinishedEvent(threadId: 'thread-1', runId: 'run-0'),
          ],
        ),
      ];
      await state.refresh();

      final loaded = state.messages.value as MessagesLoaded;
      final layout = layOutTimeline(
        messages: loaded.messages,
        bands: state.executionTrackers,
        outcomes: loaded.runOutcomes,
        streaming: null,
        activeRunId: null,
      );
      expect(
        [for (final tile in layout.tiles) tile.message.id],
        equals(['u0', 'm1']),
        reason: 'the answer stands for the run; no stopped tile beside it',
      );
      expect(layout.tiles.last.band, isNotNull);
      expect(layout.dropped, isEmpty);
    });

    test('a refresh keeps, after the runs it recorded, a run it has not',
        () async {
      // A run the backend has not finished is not in its history yet, so the
      // view's record is the only one. It ended after every run the history
      // holds, and the order is what places a run that committed nothing.
      const key = (
        serverId: 'test-server',
        roomId: 'room-1',
        threadId: 'thread-1',
      );
      api.nextThreadHistory = ThreadHistory(messages: const []);
      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      addTearDown(state.dispose);
      await Future<void>.delayed(Duration.zero);

      final session = _FakeAgentSession();
      registry.register(key, session);
      state.attachSession(session);
      session.emit(
        CancelledState.duringRun(
          threadKey: key,
          runId: 'run-1',
          conversation: Conversation(
            threadId: 'thread-1',
            runOutcomes: {'run-1': parked('run-1')},
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      api.nextThreadHistory = ThreadHistory(
        messages: const [],
        runOutcomes: {
          'run-0': NoResponseTile.finished(runId: 'run-0', thinkingText: ''),
        },
      );
      await state.refresh();

      final loaded = state.messages.value as MessagesLoaded;
      expect(loaded.runOutcomes.keys, equals(['run-0', 'run-1']));
      expect(loaded.runOutcomes['run-1']!.reason, TerminalReason.cancelled);
    });

    test('a reloaded thread carries how its stored runs ended', () async {
      // The backend replays a run that ended saying nothing as an outcome and
      // nothing else, so if the load drops it that run's work has no tile.
      api.nextThreadHistory = ThreadHistory(
        messages: const [],
        runOutcomes: {'run-0': parked('run-0')},
      );

      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      addTearDown(state.dispose);
      await Future<void>.delayed(Duration.zero);

      final loaded = state.messages.value as MessagesLoaded;
      expect(loaded.runOutcomes['run-0'], isNotNull);
      expect(loaded.runOutcomes['run-0']!.thinkingText, equals('weighing it'));
    });

    test('a later run does not erase how an earlier one ended', () async {
      // A locally cancelled run is recorded nowhere the backend can replay. A
      // send that follows builds its conversation afresh, so the view is the
      // last thing holding the earlier record and must merge rather than
      // replace.
      const key = (
        serverId: 'test-server',
        roomId: 'room-1',
        threadId: 'thread-1',
      );
      final state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      addTearDown(state.dispose);
      await Future<void>.delayed(Duration.zero);

      // Each send is its own session, and the second builds its conversation
      // from scratch — so it carries only its own run.
      final first = _FakeAgentSession();
      registry.register(key, first);
      state.attachSession(first);
      first.emit(
        CancelledState.duringRun(
          threadKey: key,
          runId: 'run-0',
          conversation: Conversation(
            threadId: 'thread-1',
            runOutcomes: {'run-0': parked('run-0')},
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final second = _FakeAgentSession();
      registry.register(key, second);
      state.attachSession(second);
      second.emit(
        CompletedState(
          threadKey: key,
          runId: 'run-1',
          conversation: Conversation(
            threadId: 'thread-1',
            runOutcomes: {'run-1': parked('run-1')},
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final loaded = state.messages.value as MessagesLoaded;
      // Ordered: `layOutTimeline` reads this as the order the runs ended,
      // which is the only record of when a run that committed nothing happened.
      expect(loaded.runOutcomes.keys, equals(['run-0', 'run-1']));
    });

    test('two states differing only in outcomes are not equal', () {
      final messages = <ChatMessage>[];
      const states = <String, MessageState>{};

      expect(
        MessagesLoaded(
          messages: messages,
          messageStates: states,
          runOutcomes: {'run-0': parked('run-0')},
        ),
        isNot(
          equals(
            MessagesLoaded(messages: messages, messageStates: states),
          ),
        ),
      );
    });
  });

  group('outcomes surviving a trip away from the thread', () {
    test('a run that ended is still reported after navigating back', () async {
      // Navigating away disposes the view; coming back builds a new one from
      // the registry. A run the backend cannot replay — a local cancel — lives
      // only in what the registry kept, so losing it here loses it for good.
      const key = (
        serverId: 'test-server',
        roomId: 'room-1',
        threadId: 'thread-1',
      );
      final parked = NoResponseTile.cancelled(
        runId: 'run-0',
        thinkingText: 'weighing it',
      );

      final session = _FakeAgentSession();
      registry.register(key, session);
      session.emit(
        CancelledState.duringRun(
          threadKey: key,
          runId: 'run-0',
          conversation: Conversation(
            threadId: 'thread-1',
            runOutcomes: {'run-0': parked},
          ),
        ),
      );
      session.complete(
        const AgentSuccess(threadKey: key, output: '', runId: 'run-0'),
      );
      await Future<void>.delayed(Duration.zero);

      final restored = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: neverFollowed,
        contextWindow: Signal<int?>(null),
      );
      addTearDown(restored.dispose);
      await Future<void>.delayed(Duration.zero);

      final loaded = restored.messages.value as MessagesLoaded;
      expect(loaded.runOutcomes['run-0'], same(parked));
    });
  });

  group('a run still going on the backend', () {
    late FollowableAgUiStreamClient streams;
    late AgentRuntimeManager runtimeManager;
    late AgentRuntime runtime;
    late ThreadViewState state;

    final runInProgress = RunInProgress(
      runId: 'run-2',
      userMessage: TextMessage.create(
        id: 'user-stored',
        user: ChatUser.user,
        text: 'Still going?',
        runId: 'run-2',
      ),
    );

    void feed(BaseEvent event) =>
        streams.followed.add(DecodedEvent(event, const {}));

    setUp(() async {
      streams = FollowableAgUiStreamClient();
      connection = ServerConnection(
        serverId: 'test-server',
        api: api,
        agUiStreamClient: streams,
      );
      runtimeManager = AgentRuntimeManager(
        platform: TestPlatformConstraints(),
        toolRegistryResolver: (_) async => const ToolRegistry(),
        logger: testLogger(),
        servers: emptyServers(),
      );
      runtime = runtimeManager.getRuntime(connection);
      api.nextThreadHistory =
          ThreadHistory(messages: const [], runInProgress: runInProgress);
      state = ThreadViewState(
        connection: connection,
        auth: auth,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
        followRun: (run) =>
            runtime.follow(roomId: 'room-1', threadId: 'thread-1', run: run),
        contextWindow: Signal<int?>(null),
        onHistoryLoaded: (_, history) =>
            runtime.seedThreadHistory(state.threadKey, history),
      );
      await pumpEventQueue();
      feed(RunStartedEvent(threadId: 'thread-1', runId: 'run-2'));
      feed(const TextMessageStartEvent(messageId: 'reply'));
      feed(const TextMessageContentEvent(messageId: 'reply', delta: 'Partly'));
      await pumpEventQueue();
    });

    tearDown(() async {
      state.dispose();
      await runtimeManager.dispose();
      unawaited(streams.followed.close());
    });

    List<String> texts() => [
          for (final m in (state.messages.value as MessagesLoaded).messages)
            if (m is TextMessage) m.text,
        ];

    test(
        'a thread opened mid-run shows the message that started it and the '
        'reply as it streams', () async {
      expect(texts(), ['Still going?']);
      expect(
        state.streamingState.value,
        isA<TextStreaming>().having((s) => s.text, 'text', 'Partly'),
      );
      expect(state.activeRunId.value, 'run-2');
      expect(state.isCancellable.value, isTrue);
    });

    test('the composer sends nothing while the followed run goes on', () async {
      api.nextCreateRun = RunInfo(
        id: 'run-3',
        threadId: 'thread-1',
        createdAt: DateTime.utc(2026),
      );
      await state.sendMessage([TextPart('Too soon')], runtime);
      await pumpEventQueue();

      expect(streams.inputs, isEmpty);
    });

    test('a send after the followed run ends carries its turn', () async {
      final ended = _endedFollows();
      feed(const TextMessageContentEvent(messageId: 'reply', delta: ' done'));
      feed(const TextMessageEndEvent(messageId: 'reply'));
      feed(const RunFinishedEvent(threadId: 'thread-1', runId: 'run-2'));
      await streams.followed.close();
      await pumpEventQueue();
      expect(texts(), ['Still going?', 'Partly done']);
      expect(registry.completedOutcome(state.threadKey), isA<CompletedRun>());
      expect(ended(), [(runId: 'run-2', result: 'completed')]);

      api.nextCreateRun = RunInfo(
        id: 'run-3',
        threadId: 'thread-1',
        createdAt: DateTime.utc(2026),
      );
      await state.sendMessage([TextPart('Next')], runtime);
      // The send returns once its session starts; the run opens after.
      await pumpEventQueue();

      expect(
        [
          for (final m in streams.inputs.single.messages!) m.toJson()['content']
        ],
        ['Still going?', 'Partly done', 'Next'],
      );
    });

    test(
        'Stop while following ends the run cancelled, as Stop on a live run '
        'does, and the run is not followed again', () async {
      final skipped = _skippedFollows();
      final ended = _endedFollows();
      state.cancelRun();
      await pumpEventQueue();

      final loaded = state.messages.value as MessagesLoaded;
      expect(texts(), ['Still going?', 'Partly']);
      expect(loaded.runOutcomes['run-2']?.reason, TerminalReason.cancelled);
      expect(state.sessionState.value, isNull);
      expect(registry.completedOutcome(state.threadKey), isA<CancelledRun>());

      // The backend finishes a stopped run in its own time, so history can
      // still report it as going.
      await state.refresh();

      expect(registry.activeSession(state.threadKey), isNull);
      expect(state.sessionState.value, isNull);
      expect(skipped(), [(runId: 'run-2', reason: 'outcomeHeld')]);
      expect(ended(), [(runId: 'run-2', result: 'cancelled')]);
    });
  });

  test('a run a session here is already running is not followed a second time',
      () async {
    final skipped = _skippedFollows();
    final running = ManualAgentSession(
      (serverId: 'test-server', roomId: 'room-1', threadId: 'thread-1'),
    );
    registry.register(running.threadKey, running);
    api.nextThreadHistory = ThreadHistory(
      messages: const [],
      runInProgress: RunInProgress(
        runId: 'run-1',
        userMessage: TextMessage.create(
          id: 'u-1',
          user: ChatUser.user,
          text: 'Hi',
          runId: 'run-1',
        ),
      ),
    );

    final state = ThreadViewState(
      connection: connection,
      auth: auth,
      roomId: 'room-1',
      threadId: 'thread-1',
      registry: registry,
      followRun: (run) async => ManualAgentSession(running.threadKey),
      contextWindow: Signal<int?>(null),
    );
    await pumpEventQueue();

    expect(registry.activeSession(state.threadKey), same(running));
    expect(skipped(), [
      (runId: 'run-1', reason: 'sessionHoldsThread'),
    ]);
    state.dispose();
  });

  group('while a follow is being set up', () {
    late FollowableAgUiStreamClient streams;
    late AgentRuntimeManager runtimeManager;
    late AgentRuntime runtime;
    late List<Completer<void>> setups;
    late bool setupFails;
    late ThreadViewState state;

    final runInProgress = RunInProgress(
      runId: 'run-1',
      userMessage: TextMessage.create(
        id: 'u-1',
        user: ChatUser.user,
        text: 'Hi',
        runId: 'run-1',
      ),
    );

    /// A view whose follow waits on a gate of its own, added to [setups],
    /// before it asks the runtime, as a follow waits for a concurrency slot
    /// or for its session's extensions.
    ThreadViewState openView() => ThreadViewState(
          connection: connection,
          auth: auth,
          roomId: 'room-1',
          threadId: 'thread-1',
          registry: registry,
          followRun: (run) async {
            final gate = Completer<void>();
            setups.add(gate);
            await gate.future;
            if (setupFails) throw StateError('no session');
            return runtime.follow(
              roomId: 'room-1',
              threadId: 'thread-1',
              run: run,
            );
          },
          contextWindow: Signal<int?>(null),
        );

    setUp(() async {
      streams = FollowableAgUiStreamClient();
      connection = ServerConnection(
        serverId: 'test-server',
        api: api,
        agUiStreamClient: streams,
      );
      runtimeManager = AgentRuntimeManager(
        platform: TestPlatformConstraints(),
        toolRegistryResolver: (_) async => const ToolRegistry(),
        logger: testLogger(),
        servers: emptyServers(),
      );
      runtime = runtimeManager.getRuntime(connection);
      setups = [];
      setupFails = false;
      api.nextThreadHistory =
          ThreadHistory(messages: const [], runInProgress: runInProgress);
      state = openView();
      await pumpEventQueue();
    });

    tearDown(() async {
      state.dispose();
      await runtimeManager.dispose();
      unawaited(streams.followed.close());
    });

    test('Stop pressed then ends the run cancelled once it is followed',
        () async {
      expect(state.isCancellable.value, isTrue);

      state.cancelRun();
      setups.single.complete();
      await pumpEventQueue();

      final loaded = state.messages.value as MessagesLoaded;
      expect(loaded.runOutcomes['run-1']?.reason, TerminalReason.cancelled);
      expect(state.sessionState.value, isNull);
      expect(registry.completedOutcome(state.threadKey), isA<CancelledRun>());
    });

    test(
        'a Stop pressed during a setup that failed does not stop the next '
        'follow', () async {
      setupFails = true;
      state.cancelRun();
      setups.single.complete();
      await pumpEventQueue();
      expect(state.sessionState.value, isNull);

      setupFails = false;
      await state.refresh();
      setups.last.complete();
      await pumpEventQueue();

      expect(registry.activeSession(state.threadKey), isNotNull);
      expect(state.isCancellable.value, isTrue);
    });

    test(
        'a view left while its follow is set up does not follow, so the view '
        'opened next keeps its own follow', () async {
      final skipped = _skippedFollows();
      final left = state;
      left.dispose();
      state = openView();
      await pumpEventQueue();
      expect(setups, hasLength(2));

      // The returning view's follow is set up first; the left view's last.
      setups[1].complete();
      await pumpEventQueue();
      setups[0].complete();
      await pumpEventQueue();

      expect(state.isCancellable.value, isTrue);
      expect(registry.activeSession(state.threadKey), isNotNull);
      expect(state.messages.value, isA<MessagesLoaded>());
      final loaded = state.messages.value as MessagesLoaded;
      expect(loaded.runOutcomes, isNot(contains('run-1')));
      expect(skipped(), [(runId: 'run-1', reason: 'viewClosed')]);
    });
  });

  test(
      'a follow that fails to start frees the composer and records why, '
      'naming the run', () async {
    final sink = MemorySink();
    LogManager.instance.addSink(sink);
    addTearDown(() => LogManager.instance.removeSink(sink));
    api.nextThreadHistory = ThreadHistory(
      messages: const [],
      runInProgress: RunInProgress(
        runId: 'run-1',
        userMessage: TextMessage.create(
          id: 'u-1',
          user: ChatUser.user,
          text: 'Hi',
          runId: 'run-1',
        ),
      ),
    );
    final state = ThreadViewState(
      connection: connection,
      auth: auth,
      roomId: 'room-1',
      threadId: 'thread-1',
      registry: registry,
      followRun: (_) async => throw StateError('runtime disposed'),
      contextWindow: Signal<int?>(null),
    );
    await pumpEventQueue();

    expect(state.sessionState.value, isNull);
    final records = sink.records
        .where((r) => r.message.contains('Could not follow'))
        .toList();
    expect(records, hasLength(1));
    expect(records.single.level, LogLevel.warning);
    expect(records.single.attributes['runId'], 'run-1');
    state.dispose();
  });
}
