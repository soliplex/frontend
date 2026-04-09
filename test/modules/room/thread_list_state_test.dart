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

  test('refresh error preserves loaded threads', () async {
    api.nextThreads = [
      ThreadInfo(
        id: 'thread-1',
        roomId: 'room-1',
        name: 'Test thread',
        createdAt: DateTime(2026, 3, 1),
      ),
    ];

    final state = ThreadListState(
      connection: connection,
      roomId: 'room-1',
    );

    await Future<void>.delayed(Duration.zero);
    expect(state.threads.value, isA<ThreadsLoaded>());

    // Now make refresh fail.
    api.nextThreads = null;
    api.nextThreadsError = Exception('refresh error');
    state.refresh();

    await Future<void>.delayed(Duration.zero);

    // Should still show the loaded threads, not replace with error.
    final status = state.threads.value;
    expect(status, isA<ThreadsLoaded>());
    expect((status as ThreadsLoaded).threads.length, 1);

    state.dispose();
  });

  test('deleteThread removes thread from list', () async {
    api.nextThreads = [
      ThreadInfo(
        id: 'thread-1',
        roomId: 'room-1',
        name: 'First',
        createdAt: DateTime(2026, 1, 1),
      ),
      ThreadInfo(
        id: 'thread-2',
        roomId: 'room-1',
        name: 'Second',
        createdAt: DateTime(2026, 3, 1),
      ),
    ];

    final state = ThreadListState(
      connection: connection,
      roomId: 'room-1',
    );
    await Future<void>.delayed(Duration.zero);

    await state.deleteThread('thread-1');

    final loaded = state.threads.value as ThreadsLoaded;
    expect(loaded.threads.length, 1);
    expect(loaded.threads.single.id, 'thread-2');
    expect(api.deleteThreadCallCount, 1);
    expect(api.lastDeletedThreadId, 'thread-1');

    state.dispose();
  });

  test('deleteThread propagates API error', () async {
    api.nextThreads = [
      ThreadInfo(
        id: 'thread-1',
        roomId: 'room-1',
        name: 'First',
        createdAt: DateTime(2026, 1, 1),
      ),
    ];

    final state = ThreadListState(
      connection: connection,
      roomId: 'room-1',
    );
    await Future<void>.delayed(Duration.zero);

    api.nextDeleteThreadError = Exception('server error');

    expect(
      () => state.deleteThread('thread-1'),
      throwsA(isA<Exception>()),
    );

    // Thread should still be in the list (pessimistic — failed, no removal).
    final loaded = state.threads.value as ThreadsLoaded;
    expect(loaded.threads.length, 1);

    state.dispose();
  });

  test('renameThread updates name and preserves description', () async {
    api.nextThreads = [
      ThreadInfo(
        id: 'thread-1',
        roomId: 'room-1',
        name: 'Old Name',
        description: 'Important context',
        createdAt: DateTime(2026, 3, 1),
      ),
    ];

    final state = ThreadListState(
      connection: connection,
      roomId: 'room-1',
    );
    await Future<void>.delayed(Duration.zero);

    await state.renameThread('thread-1', 'New Name');

    final loaded = state.threads.value as ThreadsLoaded;
    expect(loaded.threads.single.name, 'New Name');
    expect(api.updateMetadataCallCount, 1);
    expect(api.lastUpdatedThreadId, 'thread-1');
    expect(api.lastUpdatedName, 'New Name');
    expect(api.lastUpdatedDescription, 'Important context');

    state.dispose();
  });

  test('renameThread rejects empty name', () async {
    api.nextThreads = [
      ThreadInfo(
        id: 'thread-1',
        roomId: 'room-1',
        name: 'Test',
        createdAt: DateTime(2026, 3, 1),
      ),
    ];

    final state = ThreadListState(
      connection: connection,
      roomId: 'room-1',
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      () => state.renameThread('thread-1', ''),
      throwsA(isA<ArgumentError>()),
    );
    expect(api.updateMetadataCallCount, 0);

    state.dispose();
  });

  test('renameThread rejects whitespace-only name', () async {
    api.nextThreads = [
      ThreadInfo(
        id: 'thread-1',
        roomId: 'room-1',
        name: 'Test',
        createdAt: DateTime(2026, 3, 1),
      ),
    ];

    final state = ThreadListState(
      connection: connection,
      roomId: 'room-1',
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      () => state.renameThread('thread-1', '   '),
      throwsA(isA<ArgumentError>()),
    );
    expect(api.updateMetadataCallCount, 0);

    state.dispose();
  });

  test('renameThread throws StateError when threads not loaded', () async {
    api.nextThreadsError = Exception('network error');

    final state = ThreadListState(
      connection: connection,
      roomId: 'room-1',
    );
    await Future<void>.delayed(Duration.zero);

    expect(state.threads.value, isA<ThreadsFailed>());
    expect(
      () => state.renameThread('thread-1', 'New Name'),
      throwsA(isA<StateError>()),
    );
    expect(api.updateMetadataCallCount, 0);

    state.dispose();
  });

  test('renameThread omits empty description instead of sending empty string',
      () async {
    api.nextThreads = [
      ThreadInfo(
        id: 'thread-1',
        roomId: 'room-1',
        name: 'Old Name',
        // description defaults to '' (empty string)
        createdAt: DateTime(2026, 3, 1),
      ),
    ];

    final state = ThreadListState(
      connection: connection,
      roomId: 'room-1',
    );
    await Future<void>.delayed(Duration.zero);

    await state.renameThread('thread-1', 'New Name');

    expect(api.lastUpdatedDescription, isNull);

    state.dispose();
  });

  test('renameThread throws StateError when thread not in cached list',
      () async {
    api.nextThreads = [
      ThreadInfo(
        id: 'thread-1',
        roomId: 'room-1',
        name: 'Only Thread',
        createdAt: DateTime(2026, 3, 1),
      ),
    ];

    final state = ThreadListState(
      connection: connection,
      roomId: 'room-1',
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      () => state.renameThread('nonexistent-id', 'New Name'),
      throwsA(isA<StateError>()),
    );
    expect(api.updateMetadataCallCount, 0);

    state.dispose();
  });

  test('renameThread propagates API error', () async {
    api.nextThreads = [
      ThreadInfo(
        id: 'thread-1',
        roomId: 'room-1',
        name: 'Old Name',
        createdAt: DateTime(2026, 3, 1),
      ),
    ];

    final state = ThreadListState(
      connection: connection,
      roomId: 'room-1',
    );
    await Future<void>.delayed(Duration.zero);

    api.nextUpdateMetadataError = Exception('server error');

    expect(
      () => state.renameThread('thread-1', 'New Name'),
      throwsA(isA<Exception>()),
    );

    // Name should remain unchanged (pessimistic — failed, no update).
    final loaded = state.threads.value as ThreadsLoaded;
    expect(loaded.threads.single.name, 'Old Name');

    state.dispose();
  });

  test('deleteThread skips API call when disposed', () async {
    api.nextThreads = [
      ThreadInfo(
        id: 'thread-1',
        roomId: 'room-1',
        name: 'Test',
        createdAt: DateTime(2026, 1, 1),
      ),
    ];

    final state = ThreadListState(
      connection: connection,
      roomId: 'room-1',
    );
    await Future<void>.delayed(Duration.zero);

    state.dispose();
    await state.deleteThread('thread-1');

    expect(api.deleteThreadCallCount, 0);
  });

  test(
      'deleteThread when threads still loading calls API but skips local update',
      () async {
    // Never resolve the initial fetch — threads stay in loading state.
    api.nextThreadsError = Exception('slow network');

    final state = ThreadListState(
      connection: connection,
      roomId: 'room-1',
    );
    await Future<void>.delayed(Duration.zero);
    expect(state.threads.value, isA<ThreadsFailed>());

    // Clear the error so deleteThread itself succeeds.
    api.nextThreadsError = null;
    await state.deleteThread('thread-1');

    expect(api.deleteThreadCallCount, 1);
    // Threads status unchanged — no optimistic removal possible.
    expect(state.threads.value, isA<ThreadsFailed>());

    state.dispose();
  });

  test('refresh() returns a Future that completes after fetch', () async {
    api.nextThreads = [
      ThreadInfo(
        id: 'thread-1',
        roomId: 'room-1',
        name: 'Original',
        createdAt: DateTime(2026, 3, 1),
      ),
    ];

    final state = ThreadListState(
      connection: connection,
      roomId: 'room-1',
    );

    await Future<void>.delayed(Duration.zero);
    expect(state.threads.value, isA<ThreadsLoaded>());

    // Update the fake to return a new title.
    api.nextThreads = [
      ThreadInfo(
        id: 'thread-1',
        roomId: 'room-1',
        name: 'Updated title',
        createdAt: DateTime(2026, 3, 1),
      ),
    ];

    // refresh() should return a Future we can await.
    await state.refresh();

    final loaded = state.threads.value as ThreadsLoaded;
    expect(loaded.threads.single.name, 'Updated title');

    state.dispose();
  });
}
