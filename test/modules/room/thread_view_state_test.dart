import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/agent_runtime_manager.dart';
import 'package:soliplex_frontend/src/modules/room/thread_view_state.dart';

import '../../helpers/fakes.dart';

ServerConnection _fakeConnection(FakeSoliplexApi api) => ServerConnection(
      serverId: 'test-server',
      api: api,
      agUiStreamClient: FakeAgUiStreamClient(),
    );

void main() {
  late FakeSoliplexApi api;
  late ServerConnection connection;

  setUp(() {
    api = FakeSoliplexApi();
    connection = _fakeConnection(api);
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
    );

    await Future<void>.delayed(Duration.zero);

    expect(state.messages.value, isA<MessagesFailed>());

    state.dispose();
  });

  test('streamingState and sessionState are null when idle', () async {
    api.nextThreadHistory = ThreadHistory(messages: const []);

    final state = ThreadViewState(
      connection: connection,
      roomId: 'room-1',
      threadId: 'thread-1',
    );

    await Future<void>.delayed(Duration.zero);

    expect(state.streamingState.value, isNull);
    expect(state.sessionState.value, isNull);

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

    test('re-fetch failure after run error sets MessagesFailed', () async {
      api.nextThreadHistory = ThreadHistory(messages: const []);

      final state = ThreadViewState(
        connection: connection,
        roomId: 'room-1',
        threadId: 'thread-1',
      );

      await Future<void>.delayed(Duration.zero);
      expect(state.messages.value, isA<MessagesLoaded>());

      // Arrange re-fetch to fail before sendMessage so that when the
      // session run fails (FakeAgUiStreamClient throws), the subsequent
      // re-fetch also fails and leaves messages in MessagesFailed.
      api.nextThreadHistoryError = Exception('re-fetch error');
      await state.sendMessage('Hello', runtime);

      // Pump the event loop until the async run failure and re-fetch
      // have both propagated.
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
        if (state.messages.value is MessagesFailed) break;
      }

      expect(state.messages.value, isA<MessagesFailed>());

      state.dispose();
    });
  });
}
