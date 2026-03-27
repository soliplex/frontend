import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/agent_runtime_manager.dart';
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
  _FakeAgentSession()
      : _runState = Signal<RunState>(const IdleState()),
        _lastExecutionEvent = Signal<ExecutionEvent?>(null);

  final Signal<RunState> _runState;
  final Signal<ExecutionEvent?> _lastExecutionEvent;
  final Completer<AgentResult> _resultCompleter = Completer<AgentResult>();

  @override
  AgentSessionState get state => AgentSessionState.running;

  @override
  ReadonlySignal<RunState> get runState => _runState;

  @override
  ReadonlySignal<ExecutionEvent?> get lastExecutionEvent => _lastExecutionEvent;

  @override
  Future<AgentResult> get result => _resultCompleter.future;

  void emit(RunState state) => _runState.value = state;

  void complete(AgentResult result) => _resultCompleter.complete(result);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
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
}
