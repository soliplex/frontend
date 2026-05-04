import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/agent_runtime_manager.dart';
import 'package:soliplex_frontend/src/modules/room/execution_tracker_extension.dart';
import 'package:soliplex_frontend/src/modules/room/human_approval_extension.dart';
import 'package:soliplex_frontend/src/modules/room/run_registry.dart';
import 'package:soliplex_frontend/src/modules/room/thread_view_state.dart';

import '../../helpers/fakes.dart';

ServerConnection _fakeConnection(FakeSoliplexApi api) => ServerConnection(
      serverId: 'test-server',
      api: api,
      agUiStreamClient: FakeAgUiStreamClient(),
    );

/// Minimal session fake for testing [ThreadViewState] signal behavior.
class _FakeAgentSession implements AgentSession {
  _FakeAgentSession({List<SessionExtension> extensions = const []})
      : _runState = Signal<RunState>(const IdleState()),
        _lastExecutionEvent = Signal<ExecutionEvent?>(null),
        _reconnectStatus = Signal<ReconnectStatus?>(null),
        _extensions = extensions;

  final Signal<RunState> _runState;
  final Signal<ExecutionEvent?> _lastExecutionEvent;
  final Signal<ReconnectStatus?> _reconnectStatus;
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

void main() {
  late FakeSoliplexApi api;
  late ServerConnection connection;
  late RunRegistry registry;

  setUp(() {
    api = FakeSoliplexApi();
    connection = _fakeConnection(api);
    registry = RunRegistry();
  });

  tearDown(() {
    registry.dispose();
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
      roomId: 'room-1',
      threadId: 'thread-1',
      registry: registry,
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
      roomId: 'room-1',
      threadId: 'thread-1',
      registry: registry,
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
      roomId: 'room-1',
      threadId: 'thread-1',
      registry: registry,
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
      roomId: 'room-1',
      threadId: 'thread-1',
      registry: registry,
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

  test('streamingState and sessionState are null when idle', () async {
    api.nextThreadHistory = ThreadHistory(messages: const []);

    final state = ThreadViewState(
      connection: connection,
      roomId: 'room-1',
      threadId: 'thread-1',
      registry: registry,
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
      roomId: 'room-1',
      threadId: 'thread-1',
      registry: registry,
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

  test('uses registry outcome instead of server fetch', () async {
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
    );
    final assistantMessage = TextMessage(
      id: 'assistant-1',
      user: ChatUser.assistant,
      createdAt: DateTime(2026, 3, 1),
      text: 'I can help with that',
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

    // Server has only the assistant message (user message not persisted yet).
    api.nextThreadHistory = ThreadHistory(messages: [assistantMessage]);

    // Now create a new ThreadViewState (simulates navigating back).
    final state = ThreadViewState(
      connection: connection,
      roomId: 'room-1',
      threadId: 'thread-1',
      registry: registry,
    );

    // Registry outcome should be applied synchronously.
    final loaded = state.messages.value as MessagesLoaded;
    expect(loaded.messages.length, 2, reason: 'should have both messages');
    expect(loaded.messages.first.id, 'user-1');

    // After server fetch completes, registry data should NOT be overwritten.
    await Future<void>.delayed(Duration.zero);

    final afterFetch = state.messages.value as MessagesLoaded;
    expect(afterFetch.messages.length, 2,
        reason: 'server fetch must not overwrite registry outcome');
    expect(afterFetch.messages.first.id, 'user-1');

    state.dispose();
  });

  group('sendMessage', () {
    late AgentRuntimeManager runtimeManager;
    late AgentRuntime runtime;

    setUp(() {
      runtimeManager = AgentRuntimeManager(
        platform: TestPlatformConstraints(),
        toolRegistryResolver: (_) async => const ToolRegistry(),
        logger: testLogger(),
      );
      runtime = runtimeManager.getRuntime(connection);
    });

    tearDown(() async {
      await runtimeManager.dispose();
    });

    test('run failure without conversation preserves existing messages',
        () async {
      api.nextThreadHistory = ThreadHistory(messages: const []);

      final state = ThreadViewState(
        connection: connection,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
      );

      await Future<void>.delayed(Duration.zero);
      expect(state.messages.value, isA<MessagesLoaded>());

      // Send a message — spawn will succeed but the run will fail
      // (FakeAgUiStreamClient throws). FailedState may have no
      // conversation, so existing messages should be preserved.
      await state.sendMessage('Hello', runtime);

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
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
      );

      await Future<void>.delayed(Duration.zero);
      expect(state.messages.value, isA<MessagesLoaded>());

      // Dispose the runtime so spawn throws.
      await runtimeManager.dispose();
      await state.sendMessage('Hello', runtime);

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
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
      );

      await Future<void>.delayed(Duration.zero);
      expect(state.messages.value, isA<MessagesLoaded>());

      // Dispose the runtime so spawn throws.
      await runtimeManager.dispose();

      // First send failure.
      await state.sendMessage('First', runtime);
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(state.lastSendError.value, isNotNull);
      expect(state.lastSendError.value!.unsentText, 'First');

      // Second send failure without manually clearing the error.
      await state.sendMessage('Second', runtime);
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
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
      );

      await Future<void>.delayed(Duration.zero);
      expect(state.messages.value, isA<MessagesLoaded>());

      // Start sendMessage but dispose before it completes.
      final sendFuture = state.sendMessage('Hello', runtime);
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
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
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
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
      );

      await Future<void>.delayed(Duration.zero);

      // Start sendMessage without awaiting — observe intermediate state.
      final future = state.sendMessage('Hello', runtime);
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
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
      );

      await Future<void>.delayed(Duration.zero);

      // Simulate an active session.
      final fakeSession = _FakeAgentSession();
      state.attachSession(fakeSession);
      expect(state.sessionState.value, isNotNull);

      // Dispose runtime so spawn would throw if called.
      await runtimeManager.dispose();

      // sendMessage should bail out before reaching spawn.
      await state.sendMessage('Hello', runtime);

      // No error means spawn was never attempted.
      expect(state.lastSendError.value, isNull);

      state.dispose();
    });

    test('cancelRun during spawn prevents session from attaching', () async {
      api.nextThreadHistory = ThreadHistory(messages: const []);

      final state = ThreadViewState(
        connection: connection,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
      );

      await Future<void>.delayed(Duration.zero);

      // Start sendMessage and immediately cancel.
      final future = state.sendMessage('Hello', runtime);
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
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
      );

      await Future<void>.delayed(Duration.zero);
      expect(state.executionTrackers, isEmpty);

      state.dispose();
    });

    test('session completing clears activeSession without crash', () async {
      api.nextThreadHistory = ThreadHistory(messages: const []);

      final state = ThreadViewState(
        connection: connection,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
      );

      await Future<void>.delayed(Duration.zero);

      // Attach a fake session and emit CompletedState.
      // This triggers _onRunState → _detachSession → _activeSession = null.
      final fakeSession = _FakeAgentSession();
      state.attachSession(fakeSession);

      final conversation = Conversation(threadId: 'thread-1');
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

      state.dispose();
    });

    test('live tracker wins over historical on detach absorb', () async {
      const threadKey = (
        serverId: 'test-server',
        roomId: 'room-1',
        threadId: 'thread-1',
      );

      // Seed history so _fetch installs a historical tracker for 'asst-1'.
      api.nextThreadHistory = ThreadHistory(
        messages: const [],
        runs: [
          RunEventBundle(
            runId: 'run-prior',
            events: const [
              TextMessageStartEvent(messageId: 'asst-1'),
              TextMessageContentEvent(messageId: 'asst-1', delta: 'historical'),
              TextMessageEndEvent(messageId: 'asst-1'),
            ],
          ),
        ],
      );

      final state = ThreadViewState(
        connection: connection,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
      );
      await Future<void>.delayed(Duration.zero);

      final historicalTracker = state.executionTrackers['asst-1'];
      expect(historicalTracker, isNotNull,
          reason: 'replayToTrackers must seed a tracker for asst-1');

      // Attach a session whose extension will produce a live tracker under
      // the same message id.
      final ext = ExecutionTrackerExtension();
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
          text: '',
        ),
      ));

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
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
      );

      await Future<void>.delayed(Duration.zero);

      await state.sendMessage('Hello', runtime);

      // Wait for terminal state
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      state.dispose();
      expect(state.executionTrackers, isEmpty);
    });
  });

  group('approval surface', () {
    test('pendingApproval is null when no session is attached', () async {
      api.nextThreadHistory = ThreadHistory(messages: const []);
      final state = ThreadViewState(
        connection: connection,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
      );
      await Future<void>.delayed(Duration.zero);

      expect(state.pendingApproval.value, isNull);

      state.dispose();
    });

    test('respondToApproval is a silent no-op when no session', () async {
      api.nextThreadHistory = ThreadHistory(messages: const []);
      final state = ThreadViewState(
        connection: connection,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
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
          roomId: 'room-1',
          threadId: 'thread-1',
          registry: registry,
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
          roomId: 'room-1',
          threadId: 'thread-1',
          registry: registry,
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
    test(
      'FailedState whose error starts with streamResumeFailedPrefix maps '
      'to friendly SendError copy',
      () async {
        api.nextThreadHistory = ThreadHistory(messages: const []);

        final state = ThreadViewState(
          connection: connection,
          roomId: 'room-1',
          threadId: 'thread-1',
          registry: registry,
        );
        await Future<void>.delayed(Duration.zero);

        final session = _FakeAgentSession();
        state.attachSession(session);

        session.emit(
          FailedState(
            threadKey: (
              serverId: 'test-server',
              roomId: 'room-1',
              threadId: 'thread-1',
            ),
            reason: FailureReason.networkLost,
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
      'FailedState with skipped-events suffix preserves the count in '
      'friendly copy',
      () async {
        api.nextThreadHistory = ThreadHistory(messages: const []);

        final state = ThreadViewState(
          connection: connection,
          roomId: 'room-1',
          threadId: 'thread-1',
          registry: registry,
        );
        await Future<void>.delayed(Duration.zero);

        final session = _FakeAgentSession();
        state.attachSession(session);

        session.emit(
          FailedState(
            threadKey: (
              serverId: 'test-server',
              roomId: 'room-1',
              threadId: 'thread-1',
            ),
            reason: FailureReason.networkLost,
            error: '$streamResumeFailedPrefix NetworkException: server gone '
                '(skipped 3 malformed events)',
          ),
        );

        final sendError = state.lastSendError.value;
        expect(sendError, isNotNull);
        expect(sendError!.error, contains('Connection lost'));
        expect(sendError.error, contains('(skipped 3 malformed events)'));

        state.dispose();
      },
    );

    test(
      'FailedState without the marker prefix passes the raw error through',
      () async {
        api.nextThreadHistory = ThreadHistory(messages: const []);

        final state = ThreadViewState(
          connection: connection,
          roomId: 'room-1',
          threadId: 'thread-1',
          registry: registry,
        );
        await Future<void>.delayed(Duration.zero);

        final session = _FakeAgentSession();
        state.attachSession(session);

        session.emit(
          FailedState(
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

    test('mirrors session.reconnectStatus into reconnectStatus signal',
        () async {
      api.nextThreadHistory = ThreadHistory(messages: const []);

      final state = ThreadViewState(
        connection: connection,
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
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
          roomId: 'room-1',
          threadId: 'thread-1',
          registry: registry,
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
          roomId: 'room-1',
          threadId: 'thread-1',
          registry: registry,
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
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
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
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
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
        roomId: 'room-1',
        threadId: 'thread-1',
        registry: registry,
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
          pendingToolCalls: const [],
          toolDepth: 0,
        ),
      );
      expect(state.isCancellable.value, isTrue);

      state.dispose();
    });
  });
}
