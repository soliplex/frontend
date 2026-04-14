import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/agent_runtime_manager.dart';
import 'package:soliplex_frontend/src/modules/room/room_state.dart';
import 'package:soliplex_frontend/src/modules/room/run_registry.dart';
import 'package:soliplex_frontend/src/modules/room/thread_list_state.dart';

import '../../helpers/fakes.dart';

ServerConnection _fakeConnection(FakeSoliplexApi api) => ServerConnection(
      serverId: 'test-server',
      api: api,
      agUiStreamClient: FakeAgUiStreamClient(),
    );

void main() {
  late FakeSoliplexApi api;
  late ServerConnection connection;
  late AgentRuntimeManager runtimeManager;
  late RunRegistry registry;

  setUp(() {
    api = FakeSoliplexApi();
    connection = _fakeConnection(api);
    runtimeManager = AgentRuntimeManager(
      platform: TestPlatformConstraints(),
      toolRegistryResolver: (_) async => const ToolRegistry(),
      logger: testLogger(),
    );
    registry = RunRegistry();
  });

  tearDown(() async {
    await runtimeManager.dispose();
    registry.dispose();
  });

  test('selectThread creates ThreadViewState', () async {
    api.nextRoom = Room(id: 'room-1', name: 'Test');
    api.nextThreads = [];
    api.nextThreadHistory = ThreadHistory(messages: const []);

    final state = RoomState(
      connection: connection,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
    );
    expect(state.activeThreadView, isNull);

    state.selectThread('thread-1');
    expect(state.activeThreadView, isNotNull);
    expect(state.activeThreadView!.threadId, 'thread-1');

    state.dispose();
  });

  test('selectThread disposes previous ThreadViewState', () async {
    api.nextRoom = Room(id: 'room-1', name: 'Test');
    api.nextThreads = [];
    api.nextThreadHistory = ThreadHistory(messages: const []);

    final state = RoomState(
      connection: connection,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
    );

    state.selectThread('thread-1');
    final first = state.activeThreadView;

    state.selectThread('thread-2');
    expect(state.activeThreadView!.threadId, 'thread-2');
    expect(state.activeThreadView, isNot(same(first)));

    state.dispose();
  });

  test('createThread error surfaces lastError', () async {
    api.nextRoom = Room(id: 'room-1', name: 'Test');
    api.nextThreads = [];
    api.nextCreateThreadError = Exception('server error');

    final state = RoomState(
      connection: connection,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
    );

    await Future<void>.delayed(Duration.zero);

    await state.createThread();

    expect(state.lastError.value, isNotNull);
    expect(state.lastError.value!.error, isA<Exception>());

    state.dispose();
  });

  test('sendToNewThread error surfaces lastError with unsent text', () async {
    api.nextRoom = Room(id: 'room-1', name: 'Test');
    api.nextThreads = [];

    final state = RoomState(
      connection: connection,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
    );

    await Future<void>.delayed(Duration.zero);

    // Dispose runtime so spawn throws.
    await runtimeManager.dispose();
    await state.sendToNewThread('Hello');

    expect(state.lastError.value, isNotNull);
    expect(state.lastError.value!.unsentText, 'Hello');

    state.dispose();
  });

  test('sendToNewThread adds thread to list locally', () async {
    final createdThread = ThreadInfo(
      id: 'spawned-thread',
      roomId: 'room-1',
      name: '',
      createdAt: DateTime(2026, 3, 25),
    );
    api.nextRoom = Room(id: 'room-1', name: 'Test');
    api.nextCreateThread = (createdThread, <String, dynamic>{});
    api.nextThreads = [];
    api.nextThreadHistory = ThreadHistory(messages: const []);

    final state = RoomState(
      connection: connection,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
    );

    await Future<void>.delayed(Duration.zero);

    await state.sendToNewThread('Hello');
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    final loaded = state.threadList.threads.value as ThreadsLoaded;
    expect(loaded.threads.any((t) => t.id == 'spawned-thread'), isTrue);

    state.dispose();
  });

  test('sessionState is spawning during sendToNewThread', () async {
    api.nextRoom = Room(id: 'room-1', name: 'Test');
    api.nextThreads = [];
    api.nextThreadHistory = ThreadHistory(messages: const []);

    final state = RoomState(
      connection: connection,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
    );

    await Future<void>.delayed(Duration.zero);

    final sendFuture = state.sendToNewThread('Hello');
    expect(state.sessionState.value, AgentSessionState.spawning);

    await sendFuture;
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    state.dispose();
  });

  test('dispose during sendToNewThread does not cancel the spawn', () async {
    api.nextRoom = Room(id: 'room-1', name: 'Test');
    api.nextThreads = [];
    api.nextThreadHistory = ThreadHistory(messages: const []);

    final state = RoomState(
      connection: connection,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
    );

    await Future<void>.delayed(Duration.zero);

    // Start sendToNewThread but dispose before spawn completes.
    final sendFuture = state.sendToNewThread('Hello');
    state.dispose();

    // Should complete without error — spawn runs to completion.
    await sendFuture;
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    // No error should be surfaced (disposed state swallows errors).
    expect(state.lastError.value, isNull);
  });

  test('createThread adds thread to list locally and selects it', () async {
    final createdThread = ThreadInfo(
      id: 'new-thread',
      roomId: 'room-1',
      name: 'New Thread',
      createdAt: DateTime(2026, 3, 25),
    );
    api.nextRoom = Room(id: 'room-1', name: 'Test');
    api.nextCreateThread = (createdThread, <String, dynamic>{});
    api.nextThreads = [];
    api.nextThreadHistory = ThreadHistory(messages: const []);

    String? navigatedThreadId;
    final state = RoomState(
      connection: connection,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
      onNavigateToThread: (id) => navigatedThreadId = id,
    );

    await Future<void>.delayed(Duration.zero);

    final threadId = await state.createThread();
    expect(threadId, 'new-thread');

    // Thread should appear in the local list without a server refresh.
    final loaded = state.threadList.threads.value as ThreadsLoaded;
    expect(loaded.threads.any((t) => t.id == 'new-thread'), isTrue);

    expect(state.activeThreadView, isNotNull);
    expect(state.activeThreadView!.threadId, 'new-thread');
    expect(navigatedThreadId, 'new-thread');

    state.dispose();
  });

  test('fetches room metadata on construction', () async {
    api.nextRoom =
        Room(id: 'room-1', name: 'Test Room', welcomeMessage: 'Hello!');
    api.nextThreads = [];

    final state = RoomState(
      connection: connection,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
    );

    expect(state.room.value, isA<RoomLoading>());

    await Future<void>.delayed(Duration.zero);

    final loaded = state.room.value as RoomLoaded;
    expect(loaded.room.name, 'Test Room');
    expect(loaded.room.welcomeMessage, 'Hello!');

    state.dispose();
  });

  test('room fetch failure emits RoomFailed', () async {
    api.nextError = Exception('network error');
    api.nextThreads = [];

    final state = RoomState(
      connection: connection,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
    );

    await Future<void>.delayed(Duration.zero);

    expect(state.room.value, isA<RoomFailed>());

    state.dispose();
  });

  test('room not found emits RoomFailed', () async {
    api.nextError = Exception('Room not found');
    api.nextThreads = [];

    final state = RoomState(
      connection: connection,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
    );

    await Future<void>.delayed(Duration.zero);

    expect(state.room.value, isA<RoomFailed>());

    state.dispose();
  });

  group('deleteThread', () {
    test('navigates to next thread after deletion', () async {
      final threads = [
        ThreadInfo(
          id: 'thread-1',
          roomId: 'room-1',
          name: 'First',
          createdAt: DateTime(2026, 3, 1),
        ),
        ThreadInfo(
          id: 'thread-2',
          roomId: 'room-1',
          name: 'Second',
          createdAt: DateTime(2026, 1, 1),
        ),
      ];
      api.nextRoom = Room(id: 'room-1', name: 'Test');
      api.nextThreads = threads;
      api.nextThreadHistory = ThreadHistory(messages: const []);

      String? navigatedId;
      final state = RoomState(
        connection: connection,
        roomId: 'room-1',
        runtimeManager: runtimeManager,
        registry: registry,
        onNavigateToThread: (id) => navigatedId = id,
      );
      await Future<void>.delayed(Duration.zero);

      state.selectThread('thread-1');
      expect(state.activeThreadView!.threadId, 'thread-1');

      await state.deleteThread('thread-1');

      expect(state.activeThreadView!.threadId, 'thread-2');
      expect(navigatedId, 'thread-2');

      state.dispose();
    });

    test('navigates to null when last thread deleted', () async {
      final threads = [
        ThreadInfo(
          id: 'thread-1',
          roomId: 'room-1',
          name: 'Only',
          createdAt: DateTime(2026, 3, 1),
        ),
      ];
      api.nextRoom = Room(id: 'room-1', name: 'Test');
      api.nextThreads = threads;
      api.nextThreadHistory = ThreadHistory(messages: const []);

      String? navigatedId = 'not-called';
      final state = RoomState(
        connection: connection,
        roomId: 'room-1',
        runtimeManager: runtimeManager,
        registry: registry,
        onNavigateToThread: (id) => navigatedId = id,
      );
      await Future<void>.delayed(Duration.zero);

      state.selectThread('thread-1');

      await state.deleteThread('thread-1');

      expect(state.activeThreadView, isNull);
      expect(navigatedId, isNull);

      state.dispose();
    });

    test('navigates to null when thread list is not Loaded', () async {
      // Initial thread-list fetch fails so ThreadListState is in
      // ThreadsFailed, not ThreadsLoaded.
      api.nextRoom = Room(id: 'room-1', name: 'Test');
      api.nextThreadsError = Exception('list fetch failed');
      api.nextThreadHistory = ThreadHistory(messages: const []);

      String? navigatedId = 'not-called';
      final state = RoomState(
        connection: connection,
        roomId: 'room-1',
        runtimeManager: runtimeManager,
        registry: registry,
        onNavigateToThread: (id) => navigatedId = id,
      );
      await Future<void>.delayed(Duration.zero);

      state.selectThread('thread-1');
      // Allow the subsequent delete API call to succeed.
      api.nextThreadsError = null;
      await state.deleteThread('thread-1');

      expect(state.activeThreadView, isNull);
      expect(navigatedId, isNull);

      state.dispose();
    });

    test('preserves active view on API error', () async {
      final threads = [
        ThreadInfo(
          id: 'thread-1',
          roomId: 'room-1',
          name: 'Test',
          createdAt: DateTime(2026, 3, 1),
        ),
      ];
      api.nextRoom = Room(id: 'room-1', name: 'Test');
      api.nextThreads = threads;
      api.nextThreadHistory = ThreadHistory(messages: const []);

      final state = RoomState(
        connection: connection,
        roomId: 'room-1',
        runtimeManager: runtimeManager,
        registry: registry,
      );
      await Future<void>.delayed(Duration.zero);

      state.selectThread('thread-1');
      final viewBefore = state.activeThreadView;

      api.nextDeleteThreadError = Exception('server error');
      expect(
        () => state.deleteThread('thread-1'),
        throwsA(isA<Exception>()),
      );

      // Active view must be preserved on failure.
      expect(state.activeThreadView, same(viewBefore));

      state.dispose();
    });

    test('non-selected thread deletion preserves selection', () async {
      final threads = [
        ThreadInfo(
          id: 'thread-1',
          roomId: 'room-1',
          name: 'First',
          createdAt: DateTime(2026, 3, 1),
        ),
        ThreadInfo(
          id: 'thread-2',
          roomId: 'room-1',
          name: 'Second',
          createdAt: DateTime(2026, 1, 1),
        ),
      ];
      api.nextRoom = Room(id: 'room-1', name: 'Test');
      api.nextThreads = threads;
      api.nextThreadHistory = ThreadHistory(messages: const []);

      String? navigatedId = 'sentinel';
      final state = RoomState(
        connection: connection,
        roomId: 'room-1',
        runtimeManager: runtimeManager,
        registry: registry,
        onNavigateToThread: (id) => navigatedId = id,
      );
      await Future<void>.delayed(Duration.zero);

      state.selectThread('thread-1');

      // Delete the non-selected thread.
      await state.deleteThread('thread-2');

      // thread-1 should still be selected, no navigation fired.
      expect(state.activeThreadView!.threadId, 'thread-1');
      expect(navigatedId, 'sentinel');

      state.dispose();
    });
  });
}
