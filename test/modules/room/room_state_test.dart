import 'dart:async';

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/auth/admin_status.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/return_to_storage.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';
import 'package:soliplex_frontend/src/modules/room/agent_runtime_manager.dart';
import 'package:soliplex_frontend/src/modules/room/composer_draft.dart';
import 'package:soliplex_frontend/src/modules/room/room_state.dart';
import 'package:soliplex_frontend/src/modules/room/run_registry.dart';
import 'package:soliplex_frontend/src/modules/room/thread_list_state.dart';
import 'package:soliplex_frontend/src/modules/room/upload_tracker_registry.dart';

import '../../helpers/fakes.dart';
import '../../helpers/test_server_entry.dart';

/// AgentRuntime whose [spawn] always errors with [AuthException]. Used to
/// drive the spawner's AuthException branch from [RoomState.sendToNewThread]
/// without disposing the runtime (which would surface a StateError on the
/// `on Object` arm instead).
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

/// [AgentRuntimeManager] that always returns the runtime it was given.
class _StubRuntimeManager extends AgentRuntimeManager {
  _StubRuntimeManager(this._runtime)
      : super(
          platform: TestPlatformConstraints(),
          toolRegistryResolver: (_) async => const ToolRegistry(),
          logger: testLogger(),
          forwardedPropsFor: (_) => () async => const {},
          servers: emptyServers(),
        );

  final AgentRuntime _runtime;

  @override
  AgentRuntime getRuntime(ServerConnection connection) => _runtime;
}

const _testUserId = 'iss-test#user';

void _activate(AuthSession auth) {
  auth.login(
    provider: const OidcProvider(
      discoveryUrl: 'https://auth.example.com/.well-known/openid-configuration',
      clientId: 'test-client',
    ),
    tokens: AuthTokens(
      accessToken: testJwt({'iss': 'iss-test', 'sub': 'user'}),
      refreshToken: 'refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    ),
  );
}

ServerConnection _fakeConnection(FakeSoliplexApi api) => ServerConnection(
      serverId: 'test-server',
      api: api,
      agUiStreamClient: FakeAgUiStreamClient(),
    );

ServerEntry _fakeServerEntry(ServerConnection connection) => ServerEntry(
      serverId: connection.serverId,
      alias: connection.serverId,
      serverUrl: Uri.parse('https://${connection.serverId}.example.com'),
      auth: AuthSession(refreshService: FakeTokenRefreshService()),
      httpClient: FakeHttpClient(),
      connection: connection,
      adminStatus: AdminStatus(
        api: connection.api,
        serverId: connection.serverId,
      ),
    );

void main() {
  late FakeSoliplexApi api;
  late ServerConnection connection;
  late ServerEntry serverEntry;
  late AgentRuntimeManager runtimeManager;
  late RunRegistry registry;
  late Signal<Map<String, ServerEntry>> servers;
  late UploadTrackerRegistry uploadRegistry;

  setUp(() {
    api = FakeSoliplexApi();
    connection = _fakeConnection(api);
    serverEntry = _fakeServerEntry(connection);
    runtimeManager = AgentRuntimeManager(
      platform: TestPlatformConstraints(),
      toolRegistryResolver: (_) async => const ToolRegistry(),
      logger: testLogger(),
      forwardedPropsFor: (_) => () async => const {},
      servers: emptyServers(),
    );
    registry = RunRegistry(servers: emptyServers());
    servers = Signal({serverEntry.serverId: serverEntry});
    uploadRegistry = UploadTrackerRegistry(servers: servers);
  });

  tearDown(() async {
    await runtimeManager.dispose();
    registry.dispose();
    uploadRegistry.dispose();
    servers.dispose();
  });

  test('selectThread creates ThreadViewState', () async {
    api.nextRoom = Room(id: 'room-1', name: 'Test');
    api.nextThreads = [];
    api.nextThreadHistory = ThreadHistory(messages: const []);

    final state = RoomState(
      serverEntry: serverEntry,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
      uploadRegistry: uploadRegistry,
    );
    expect(state.activeThreadView, isNull);

    state.selectThread('thread-1');
    expect(state.activeThreadView, isNotNull);
    expect(state.activeThreadView!.threadId, 'thread-1');

    state.dispose();
  });

  test(
      'a thread opened while a run is still going follows the run in the '
      "room's runtime", () async {
    final streams = FollowableAgUiStreamClient();
    addTearDown(() => unawaited(streams.followed.close()));
    final following = _fakeServerEntry(
      ServerConnection(
        serverId: 'test-server',
        api: api,
        agUiStreamClient: streams,
      ),
    );
    api.nextRoom = Room(id: 'room-1', name: 'Test');
    api.nextThreads = [];
    api.nextThreadHistory = ThreadHistory(
      messages: const [],
      runInProgress: RunInProgress(
        runId: 'run-1',
        userMessage: TextMessage.create(
          id: 'u-1',
          user: ChatUser.user,
          text: 'Still going?',
          runId: 'run-1',
        ),
      ),
    );
    final state = RoomState(
      serverEntry: following,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
      uploadRegistry: uploadRegistry,
    );
    addTearDown(state.dispose);

    state.selectThread('thread-1');
    await pumpEventQueue();
    streams.followed.add(
      DecodedEvent(
        const TextMessageContentEvent(messageId: 'reply', delta: 'Partly'),
        const {},
      ),
    );
    await pumpEventQueue();

    final view = state.activeThreadView!;
    expect(
      state.runtime.getSession(view.threadKey),
      same(registry.activeSession(view.threadKey)),
    );
    expect(view.activeRunId.value, 'run-1');
  });

  test('selectThread disposes previous ThreadViewState', () async {
    api.nextRoom = Room(id: 'room-1', name: 'Test');
    api.nextThreads = [];
    api.nextThreadHistory = ThreadHistory(messages: const []);

    final state = RoomState(
      serverEntry: serverEntry,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
      uploadRegistry: uploadRegistry,
    );

    state.selectThread('thread-1');
    final first = state.activeThreadView;

    state.selectThread('thread-2');
    expect(state.activeThreadView!.threadId, 'thread-2');
    expect(state.activeThreadView, isNot(same(first)));

    state.dispose();
  });

  test('hands the loaded room window to the thread view', () async {
    api.nextThreads = const [];
    api.nextThreadHistory = ThreadHistory(messages: const []);
    api.nextRoom = Room(
      id: 'room-1',
      name: 'General',
      agent: DefaultRoomAgent(
        id: 'room-room-1',
        providerType: 'ollama',
        contextWindow: 16384,
      ),
    );
    final state = RoomState(
      serverEntry: serverEntry,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
      uploadRegistry: uploadRegistry,
    );
    addTearDown(state.dispose);
    state.selectThread('thread-1');

    expect(
        state.activeThreadView!.contextUsage.usage.value.contextWindow, isNull,
        reason: 'the room has not loaded yet');
    await Future<void>.delayed(Duration.zero);

    expect(
        state.activeThreadView!.contextUsage.usage.value.contextWindow, 16384);
  });

  test('createThread error surfaces lastError', () async {
    api.nextRoom = Room(id: 'room-1', name: 'Test');
    api.nextThreads = [];
    api.nextCreateThreadError = Exception('server error');

    final state = RoomState(
      serverEntry: serverEntry,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
      uploadRegistry: uploadRegistry,
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
      serverEntry: serverEntry,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
      uploadRegistry: uploadRegistry,
    );

    await Future<void>.delayed(Duration.zero);

    // Dispose runtime so spawn throws.
    await runtimeManager.dispose();
    await state.sendToNewThread([
      const TextPart('Hello'),
      ImagePart(bytes: Uint8List.fromList([0x89]), mimeType: 'image/png'),
    ]);

    expect(state.lastError.value, isNotNull);
    expect(
      state.lastError.value!.unsentText,
      'Hello$composerDraftImageMarker',
      reason: 'SendError carries a string, so a failed send restores the text '
          "with a marker holding the image's place rather than dropping it "
          'where the user cannot see it go.',
    );

    state.dispose();
  });

  test('a Stop on a disposed room does not cancel the run its send started',
      () async {
    // Disposing leaves a spawn going, so the run reaches the registry and the
    // thread shows it when reopened. A screen that outlived the room can
    // still press Stop on it.
    api.nextRoom = Room(id: 'room-1', name: 'Test');
    api.nextCreateThread = (
      ThreadInfo(
        id: 'spawned-thread',
        roomId: 'room-1',
        createdAt: DateTime(2026, 3, 25),
      ),
      <String, dynamic>{},
    );
    api.nextThreads = [];
    api.nextThreadHistory = ThreadHistory(messages: const []);
    final state = RoomState(
      serverEntry: serverEntry,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
      uploadRegistry: uploadRegistry,
    );
    await Future<void>.delayed(Duration.zero);
    final future = state.sendToNewThread([const TextPart('Hello')]);
    state.dispose();

    state.cancelSpawn();
    await future;
    await pumpEventQueue();

    const key = (
      serverId: 'test-server',
      roomId: 'room-1',
      threadId: 'spawned-thread',
    );
    expect(
      registry.activeSession(key) ?? registry.completedOutcome(key),
      isNotNull,
    );
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
      serverEntry: serverEntry,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
      uploadRegistry: uploadRegistry,
    );

    await Future<void>.delayed(Duration.zero);

    await state.sendToNewThread([TextPart('Hello')]);
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
      serverEntry: serverEntry,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
      uploadRegistry: uploadRegistry,
    );

    await Future<void>.delayed(Duration.zero);

    final sendFuture = state.sendToNewThread([TextPart('Hello')]);
    expect(state.sessionState.value, AgentSessionState.spawning);

    await sendFuture;
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    state.dispose();
  });

  test(
      'a room left while a new thread spawns still registers its run, so the '
      'thread shows it running when reopened', () async {
    api.nextRoom = Room(id: 'room-1', name: 'Test');
    api.nextCreateThread = (
      ThreadInfo(
        id: 'spawned-thread',
        roomId: 'room-1',
        createdAt: DateTime(2026, 3, 25),
      ),
      <String, dynamic>{},
    );
    api.nextThreads = [];
    api.nextThreadHistory = ThreadHistory(messages: const []);
    final state = RoomState(
      serverEntry: serverEntry,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
      uploadRegistry: uploadRegistry,
    );
    await Future<void>.delayed(Duration.zero);

    final sendFuture = state.sendToNewThread([TextPart('Hello')]);
    state.dispose();
    await sendFuture;
    await pumpEventQueue();

    const key = (
      serverId: 'test-server',
      roomId: 'room-1',
      threadId: 'spawned-thread',
    );
    expect(
      registry.activeSession(key) ?? registry.completedOutcome(key),
      isNotNull,
    );
  });

  test('a spawn that fails after the room is left surfaces no error', () async {
    api.nextRoom = Room(id: 'room-1', name: 'Test');
    api.nextThreads = [];
    api.nextThreadHistory = ThreadHistory(messages: const []);

    final state = RoomState(
      serverEntry: serverEntry,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
      uploadRegistry: uploadRegistry,
    );

    await Future<void>.delayed(Duration.zero);

    // No thread can be created, so the spawn fails, after the room is left.
    final sendFuture = state.sendToNewThread([TextPart('Hello')]);
    state.dispose();

    await sendFuture;
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }

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
      serverEntry: serverEntry,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
      uploadRegistry: uploadRegistry,
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
      serverEntry: serverEntry,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
      uploadRegistry: uploadRegistry,
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
      serverEntry: serverEntry,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
      uploadRegistry: uploadRegistry,
    );

    await Future<void>.delayed(Duration.zero);

    expect(state.room.value, isA<RoomFailed>());

    state.dispose();
  });

  test('room not found emits RoomFailed', () async {
    api.nextError = Exception('Room not found');
    api.nextThreads = [];

    final state = RoomState(
      serverEntry: serverEntry,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
      uploadRegistry: uploadRegistry,
    );

    await Future<void>.delayed(Duration.zero);

    expect(state.room.value, isA<RoomFailed>());

    state.dispose();
  });

  test('runningThreadIds clears when the underlying session terminates',
      () async {
    api.nextRoom = Room(id: 'room-1', name: 'Test');
    api.nextThreads = [];
    api.nextThreadHistory = ThreadHistory(messages: const []);

    final state = RoomState(
      serverEntry: serverEntry,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
      uploadRegistry: uploadRegistry,
    );

    final key = (
      serverId: 'test-server',
      roomId: 'room-1',
      threadId: 'thread-A',
    );
    final session = ManualAgentSession(key);
    registry.register(key, session);

    expect(state.runningThreadIds.value, {'thread-A'});

    session.completeAsCancelled();
    await Future<void>.delayed(Duration.zero);

    expect(state.runningThreadIds.value, isEmpty);

    state.dispose();
  });

  test('a finished run for a non-selected thread refreshes the thread list',
      () async {
    api.nextRoom = Room(id: 'room-1', name: 'Test');
    api.nextThreads = [];
    api.nextThreadHistory = ThreadHistory(messages: const []);

    final state = RoomState(
      serverEntry: serverEntry,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
      uploadRegistry: uploadRegistry,
    );
    await Future<void>.delayed(Duration.zero);
    final before = api.getThreadsCallCount;

    final key =
        (serverId: 'test-server', roomId: 'room-1', threadId: 'thread-A');
    final session = ManualAgentSession(key);
    registry.register(key, session);
    session.completeAsCancelled();

    // The refresh is debounced (300ms); wait past the window for the fetch.
    await Future<void>.delayed(const Duration(milliseconds: 350));

    expect(api.getThreadsCallCount, before + 1);

    state.dispose();
  });

  test('a finished run for the selected thread does not refresh the list',
      () async {
    api.nextRoom = Room(id: 'room-1', name: 'Test');
    api.nextThreads = [];
    api.nextThreadHistory = ThreadHistory(messages: const []);

    final state = RoomState(
      serverEntry: serverEntry,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
      uploadRegistry: uploadRegistry,
    );
    state.selectThread('thread-A');
    await Future<void>.delayed(Duration.zero);
    final before = api.getThreadsCallCount;

    final key =
        (serverId: 'test-server', roomId: 'room-1', threadId: 'thread-A');
    final session = ManualAgentSession(key);
    registry.register(key, session);
    session.completeAsCancelled();

    await Future<void>.delayed(const Duration(milliseconds: 350));

    // You're looking at the thread, so its completion must not trigger a fetch.
    expect(api.getThreadsCallCount, before);

    state.dispose();
  });

  test('runningThreadIds excludes runs from other rooms and other servers',
      () async {
    api.nextRoom = Room(id: 'room-1', name: 'Test');
    api.nextThreads = [];
    api.nextThreadHistory = ThreadHistory(messages: const []);

    final state = RoomState(
      serverEntry: serverEntry,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      registry: registry,
      uploadRegistry: uploadRegistry,
    );

    final runtime = runtimeManager.getRuntime(connection);
    final session1 = await runtime.spawn(
        roomId: 'room-1', prompt: [TextPart('t')], threadId: 'thread-A');
    final session2 = await runtime.spawn(
        roomId: 'room-2', prompt: [TextPart('t')], threadId: 'thread-B');
    final session3 = await runtime.spawn(
        roomId: 'room-1', prompt: [TextPart('t')], threadId: 'thread-C');

    registry.register(
      (serverId: 'test-server', roomId: 'room-1', threadId: 'thread-A'),
      session1,
    );
    registry.register(
      (serverId: 'test-server', roomId: 'room-2', threadId: 'thread-B'),
      session2,
    );
    registry.register(
      (serverId: 'other-server', roomId: 'room-1', threadId: 'thread-C'),
      session3,
    );

    expect(state.runningThreadIds.value, {'thread-A'});

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
        serverEntry: serverEntry,
        roomId: 'room-1',
        runtimeManager: runtimeManager,
        registry: registry,
        uploadRegistry: uploadRegistry,
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
        serverEntry: serverEntry,
        roomId: 'room-1',
        runtimeManager: runtimeManager,
        registry: registry,
        uploadRegistry: uploadRegistry,
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
        serverEntry: serverEntry,
        roomId: 'room-1',
        runtimeManager: runtimeManager,
        registry: registry,
        uploadRegistry: uploadRegistry,
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
        serverEntry: serverEntry,
        roomId: 'room-1',
        runtimeManager: runtimeManager,
        registry: registry,
        uploadRegistry: uploadRegistry,
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
        serverEntry: serverEntry,
        roomId: 'room-1',
        runtimeManager: runtimeManager,
        registry: registry,
        uploadRegistry: uploadRegistry,
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

  group('_fetchRoom auth funneling', () {
    test('AuthException funnels through markSessionExpired', () async {
      _activate(serverEntry.auth);
      api.nextThreads = [];
      api.nextError = AuthException(
        statusCode: 401,
        message: 'JWT validation failed',
      );

      final state = RoomState(
        serverEntry: serverEntry,
        roomId: 'room-1',
        runtimeManager: runtimeManager,
        registry: registry,
        uploadRegistry: uploadRegistry,
      );

      await Future<void>.delayed(Duration.zero);

      expect(serverEntry.auth.session.value, isA<ExpiredSession>());
      expect(
        state.room.value,
        isA<RoomLoading>(),
        reason: 'On AuthException we leave RoomLoading so the route guard '
            'can redirect without a transient RoomFailed banner.',
      );

      state.dispose();
    });

    test('PermissionDeniedException surfaces as RoomFailed', () async {
      _activate(serverEntry.auth);
      api.nextThreads = [];
      api.nextError = PermissionDeniedException(
        statusCode: 403,
        message: 'Forbidden',
      );

      final state = RoomState(
        serverEntry: serverEntry,
        roomId: 'room-1',
        runtimeManager: runtimeManager,
        registry: registry,
        uploadRegistry: uploadRegistry,
      );

      await Future<void>.delayed(Duration.zero);

      expect(serverEntry.auth.session.value, isA<ActiveSession>());
      expect(state.room.value, isA<RoomFailed>());

      state.dispose();
    });

    test('generic error still surfaces as RoomFailed (regression)', () async {
      _activate(serverEntry.auth);
      api.nextThreads = [];
      api.nextError = Exception('network down');

      final state = RoomState(
        serverEntry: serverEntry,
        roomId: 'room-1',
        runtimeManager: runtimeManager,
        registry: registry,
        uploadRegistry: uploadRegistry,
      );

      await Future<void>.delayed(Duration.zero);

      expect(serverEntry.auth.session.value, isA<ActiveSession>());
      expect(state.room.value, isA<RoomFailed>());

      state.dispose();
    });
  });

  group('createThread auth funneling', () {
    test('AuthException funnels through markSessionExpired', () async {
      _activate(serverEntry.auth);
      api.nextRoom = Room(id: 'room-1', name: 'Test');
      api.nextThreads = [];
      api.nextCreateThreadError = AuthException(
        statusCode: 401,
        message: 'JWT validation failed',
      );

      final state = RoomState(
        serverEntry: serverEntry,
        roomId: 'room-1',
        runtimeManager: runtimeManager,
        registry: registry,
        uploadRegistry: uploadRegistry,
      );

      await Future<void>.delayed(Duration.zero);

      final id = await state.createThread();

      expect(id, isNull);
      expect(serverEntry.auth.session.value, isA<ExpiredSession>());
      expect(
        state.lastError.value,
        isNull,
        reason: 'AuthException is funneled, not surfaced inline.',
      );

      state.dispose();
    });

    test('PermissionDeniedException surfaces inline', () async {
      _activate(serverEntry.auth);
      api.nextRoom = Room(id: 'room-1', name: 'Test');
      api.nextThreads = [];
      api.nextCreateThreadError = PermissionDeniedException(
        statusCode: 403,
        message: 'Forbidden',
      );

      final state = RoomState(
        serverEntry: serverEntry,
        roomId: 'room-1',
        runtimeManager: runtimeManager,
        registry: registry,
        uploadRegistry: uploadRegistry,
      );

      await Future<void>.delayed(Duration.zero);

      final id = await state.createThread();

      expect(id, isNull);
      expect(serverEntry.auth.session.value, isA<ActiveSession>());
      expect(state.lastError.value, isNotNull);
      expect(state.lastError.value!.error, isA<PermissionDeniedException>());

      state.dispose();
    });

    test('generic error still surfaces inline (regression)', () async {
      _activate(serverEntry.auth);
      api.nextRoom = Room(id: 'room-1', name: 'Test');
      api.nextThreads = [];
      api.nextCreateThreadError = Exception('network down');

      final state = RoomState(
        serverEntry: serverEntry,
        roomId: 'room-1',
        runtimeManager: runtimeManager,
        registry: registry,
        uploadRegistry: uploadRegistry,
      );

      await Future<void>.delayed(Duration.zero);

      final id = await state.createThread();

      expect(id, isNull);
      expect(serverEntry.auth.session.value, isA<ActiveSession>());
      expect(state.lastError.value, isNotNull);

      state.dispose();
    });
  });

  group('sendToNewThread auth funneling', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('AuthException persists composer text for the auth roundtrip',
        () async {
      // Drives the full path: runtime throws AuthException at spawn time
      // → SessionSpawner funnels via markSessionExpired → RoomState's
      // onAuthExpired callback persists the prompt to ReturnToStorage so
      // the composer survives the route guard redirect.
      _activate(serverEntry.auth);
      api.nextRoom = Room(id: 'room-1', name: 'Test');
      api.nextThreads = [];

      final state = RoomState(
        serverEntry: serverEntry,
        roomId: 'room-1',
        runtimeManager: _StubRuntimeManager(
          _AuthExceptionThrowingRuntime(connection),
        ),
        registry: registry,
        uploadRegistry: uploadRegistry,
      );
      await Future<void>.delayed(Duration.zero);

      await state.sendToNewThread([
        const TextPart('half-written question'),
        ImagePart(bytes: Uint8List.fromList([0x89]), mimeType: 'image/png'),
      ]);
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(serverEntry.auth.session.value, isA<ExpiredSession>());
      expect(
        state.lastError.value,
        isNull,
        reason: 'AuthException is funneled, not surfaced inline.',
      );

      final restored = await ReturnToStorage.loadComposer(
        serverId: 'test-server',
        userId: _testUserId,
        roomId: 'room-1',
      );
      expect(
        restored,
        'half-written question$composerDraftImageMarker',
        reason: 'RoomState.sendToNewThread must wire composer persistence '
            "as the spawner's onAuthExpired hook; without it the user's "
            'draft is dropped on the floor by the redirect. Storage holds a '
            "string, so the draft keeps the image's position and not its "
            'bytes.',
      );

      state.dispose();
    });
  });
}
