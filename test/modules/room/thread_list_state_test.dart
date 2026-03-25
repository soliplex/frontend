import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

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

  setUp(() {
    api = FakeSoliplexApi();
    connection = _fakeConnection(api);
  });

  test('fetches threads sorted by createdAt descending', () async {
    final older = ThreadInfo(
      id: 'thread-1',
      roomId: 'room-1',
      name: 'Older thread',
      createdAt: DateTime(2026, 1, 1),
    );
    final newer = ThreadInfo(
      id: 'thread-2',
      roomId: 'room-1',
      name: 'Newer thread',
      createdAt: DateTime(2026, 3, 1),
    );
    api.nextThreads = [older, newer];

    final state = ThreadListState(
      connection: connection,
      roomId: 'room-1',
    );

    // Should start as loading
    expect(state.threads.value, isA<ThreadsLoading>());

    // Wait for fetch to complete
    await Future<void>.delayed(Duration.zero);

    final loaded = state.threads.value as ThreadsLoaded;
    expect(loaded.threads.length, 2);
    expect(loaded.threads.first.id, 'thread-2'); // newer first
    expect(loaded.threads.last.id, 'thread-1');

    state.dispose();
  });

  test('exposes failed status on fetch error', () async {
    api.nextThreadsError = Exception('network error');

    final state = ThreadListState(
      connection: connection,
      roomId: 'room-1',
    );

    await Future<void>.delayed(Duration.zero);

    expect(state.threads.value, isA<ThreadsFailed>());

    state.dispose();
  });
}
