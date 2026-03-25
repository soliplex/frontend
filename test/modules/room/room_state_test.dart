import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/agent_runtime_manager.dart';
import 'package:soliplex_frontend/src/modules/room/room_state.dart';

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

  setUp(() {
    api = FakeSoliplexApi();
    connection = _fakeConnection(api);
    runtimeManager = AgentRuntimeManager(
      platform: TestPlatformConstraints(),
      toolRegistryResolver: (_) async => const ToolRegistry(),
      logger: testLogger(),
    );
  });

  tearDown(() async {
    await runtimeManager.dispose();
  });

  test('selectThread creates ThreadViewState', () async {
    api.nextThreads = [];
    api.nextThreadHistory = ThreadHistory(messages: const []);

    final state = RoomState(
      connection: connection,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
    );
    expect(state.activeThreadView, isNull);

    state.selectThread('thread-1');
    expect(state.activeThreadView, isNotNull);
    expect(state.activeThreadView!.threadId, 'thread-1');

    state.dispose();
  });

  test('selectThread disposes previous ThreadViewState', () async {
    api.nextThreads = [];
    api.nextThreadHistory = ThreadHistory(messages: const []);

    final state = RoomState(
      connection: connection,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
    );

    state.selectThread('thread-1');
    final first = state.activeThreadView;

    state.selectThread('thread-2');
    expect(state.activeThreadView!.threadId, 'thread-2');
    expect(state.activeThreadView, isNot(same(first)));

    state.dispose();
  });

  test('createThread calls API, refreshes list, and selects thread', () async {
    final createdThread = ThreadInfo(
      id: 'new-thread',
      roomId: 'room-1',
      name: 'New Thread',
      createdAt: DateTime(2026, 3, 25),
    );
    api.nextCreateThread = (createdThread, <String, dynamic>{});
    api.nextThreads = [];
    api.nextThreadHistory = ThreadHistory(messages: const []);

    String? navigatedThreadId;
    final state = RoomState(
      connection: connection,
      roomId: 'room-1',
      runtimeManager: runtimeManager,
      onNavigateToThread: (id) => navigatedThreadId = id,
    );

    await Future<void>.delayed(Duration.zero);

    // After create, set list to return the new thread
    api.nextThreads = [createdThread];

    final threadId = await state.createThread();
    expect(threadId, 'new-thread');

    // Wait for thread list refresh
    await Future<void>.delayed(Duration.zero);

    expect(state.activeThreadView, isNotNull);
    expect(state.activeThreadView!.threadId, 'new-thread');
    expect(navigatedThreadId, 'new-thread');

    state.dispose();
  });
}
