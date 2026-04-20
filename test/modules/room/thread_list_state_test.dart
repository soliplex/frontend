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

    final state = ThreadListState(connection: connection, roomId: 'room-1');

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

    final state = ThreadListState(connection: connection, roomId: 'room-1');

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

    final state = ThreadListState(connection: connection, roomId: 'room-1');

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

    final state = ThreadListState(connection: connection, roomId: 'room-1');
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

    final state = ThreadListState(connection: connection, roomId: 'room-1');
    await Future<void>.delayed(Duration.zero);

    api.nextDeleteThreadError = Exception('server error');

    expect(() => state.deleteThread('thread-1'), throwsA(isA<Exception>()));

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

    final state = ThreadListState(connection: connection, roomId: 'room-1');
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

  test('renameThread throws StateError when threads not loaded', () async {
    api.nextThreadsError = Exception('network error');

    final state = ThreadListState(connection: connection, roomId: 'room-1');
    await Future<void>.delayed(Duration.zero);

    expect(state.threads.value, isA<ThreadsFailed>());
    expect(
      () => state.renameThread('thread-1', 'New Name'),
      throwsA(isA<StateError>()),
    );
    expect(api.updateMetadataCallCount, 0);

    state.dispose();
  });

  test(
    'renameThread omits empty description instead of sending empty string',
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

      final state = ThreadListState(connection: connection, roomId: 'room-1');
      await Future<void>.delayed(Duration.zero);

      await state.renameThread('thread-1', 'New Name');

      expect(api.lastUpdatedDescription, isNull);

      state.dispose();
    },
  );

  test(
    'renameThread throws StateError when thread not in cached list',
    () async {
      api.nextThreads = [
        ThreadInfo(
          id: 'thread-1',
          roomId: 'room-1',
          name: 'Only Thread',
          createdAt: DateTime(2026, 3, 1),
        ),
      ];

      final state = ThreadListState(connection: connection, roomId: 'room-1');
      await Future<void>.delayed(Duration.zero);

      expect(
        () => state.renameThread('nonexistent-id', 'New Name'),
        throwsA(isA<StateError>()),
      );
      expect(api.updateMetadataCallCount, 0);

      state.dispose();
    },
  );

  test('renameThread propagates API error', () async {
    api.nextThreads = [
      ThreadInfo(
        id: 'thread-1',
        roomId: 'room-1',
        name: 'Old Name',
        createdAt: DateTime(2026, 3, 1),
      ),
    ];

    final state = ThreadListState(connection: connection, roomId: 'room-1');
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

    final state = ThreadListState(connection: connection, roomId: 'room-1');
    await Future<void>.delayed(Duration.zero);

    state.dispose();
    await state.deleteThread('thread-1');

    expect(api.deleteThreadCallCount, 0);
  });

  test('deleteThread disposed during await does not mutate list', () async {
    final thread = ThreadInfo(
      id: 'thread-1',
      roomId: 'room-1',
      name: 'Test',
      createdAt: DateTime(2026, 1, 1),
    );
    api.nextThreads = [thread];

    final state = ThreadListState(connection: connection, roomId: 'room-1');
    await Future<void>.delayed(Duration.zero);

    // Start delete, synchronously dispose before the API future resolves.
    final pending = state.deleteThread('thread-1');
    state.dispose();
    await pending;

    // API was called, but local list must not have been updated.
    expect(api.deleteThreadCallCount, 1);
    final loaded = state.threads.value as ThreadsLoaded;
    expect(loaded.threads.single.id, 'thread-1');
  });

  test('renameThread disposed during await does not mutate list', () async {
    final thread = ThreadInfo(
      id: 'thread-1',
      roomId: 'room-1',
      name: 'Old Name',
      createdAt: DateTime(2026, 1, 1),
    );
    api.nextThreads = [thread];

    final state = ThreadListState(connection: connection, roomId: 'room-1');
    await Future<void>.delayed(Duration.zero);

    final pending = state.renameThread('thread-1', 'New Name');
    state.dispose();
    await pending;

    expect(api.updateMetadataCallCount, 1);
    final loaded = state.threads.value as ThreadsLoaded;
    expect(loaded.threads.single.name, 'Old Name');
  });

  group('createThread', () {
    test('returns server result and inserts thread into loaded list', () async {
      api.nextThreads = [];
      final state = ThreadListState(connection: connection, roomId: 'room-1');
      await Future<void>.delayed(Duration.zero);

      final created = ThreadInfo(
        id: 'thread-new',
        roomId: 'room-1',
        name: 'Fresh',
        createdAt: DateTime(2026, 3, 1),
      );
      final initialAguiState = {'messages': <dynamic>[]};
      api.nextCreateThread = (created, initialAguiState);

      final result = await state.createThread();

      expect(result, isNotNull);
      expect(result!.$1.id, 'thread-new');
      expect(result.$2, same(initialAguiState));
      final loaded = state.threads.value as ThreadsLoaded;
      expect(loaded.threads.single.id, 'thread-new');

      state.dispose();
    });

    test('disposed before call returns null without hitting API', () async {
      api.nextThreads = [];
      final state = ThreadListState(connection: connection, roomId: 'room-1');
      await Future<void>.delayed(Duration.zero);

      state.dispose();
      final result = await state.createThread();

      expect(result, isNull);
      // nextCreateThread was never set; if the API had been called it would
      // have thrown StateError.
    });

    test('disposed during await returns null without mutating list', () async {
      api.nextThreads = [];
      final state = ThreadListState(connection: connection, roomId: 'room-1');
      await Future<void>.delayed(Duration.zero);

      api.nextCreateThread = (
        ThreadInfo(
          id: 'thread-new',
          roomId: 'room-1',
          name: 'Fresh',
          createdAt: DateTime(2026, 3, 1),
        ),
        <String, dynamic>{},
      );

      final pending = state.createThread();
      state.dispose();
      final result = await pending;

      expect(result, isNull);
      final loaded = state.threads.value as ThreadsLoaded;
      expect(loaded.threads, isEmpty);
    });
  });

  test('deleteThread from non-loaded state calls the API and schedules a '
      'fresh fetch to reconcile', () async {
    // Initial fetch fails: state ends up in ThreadsFailed.
    api.nextThreadsError = Exception('slow network');

    final state = ThreadListState(connection: connection, roomId: 'room-1');
    await Future<void>.delayed(Duration.zero);
    expect(state.threads.value, isA<ThreadsFailed>());

    // Clear the error and seed the next fetch with the post-delete
    // server state.
    api.nextThreadsError = null;
    api.nextThreads = [
      ThreadInfo(
        id: 'thread-other',
        roomId: 'room-1',
        name: 'Other',
        createdAt: DateTime(2026, 2, 1),
      ),
    ];

    await state.deleteThread('thread-1');
    // deleteThread scheduled a fresh fetch; let it resolve.
    await Future<void>.delayed(Duration.zero);

    expect(api.deleteThreadCallCount, 1);
    expect(state.threads.value, isA<ThreadsLoaded>());
    final loaded = state.threads.value as ThreadsLoaded;
    expect(loaded.threads.single.id, 'thread-other');

    state.dispose();
  });

  group('noteSpawnedThread', () {
    test(
      'inserts thread into loaded list sorted by createdAt descending',
      () async {
        final existing = ThreadInfo(
          id: 'thread-1',
          roomId: 'room-1',
          name: 'Existing',
          createdAt: DateTime(2026, 1, 1),
        );
        api.nextThreads = [existing];

        final state = ThreadListState(connection: connection, roomId: 'room-1');
        await Future<void>.delayed(Duration.zero);

        final newer = ThreadInfo(
          id: 'thread-2',
          roomId: 'room-1',
          name: 'Newer',
          createdAt: DateTime(2026, 3, 1),
        );
        state.noteSpawnedThread(newer);

        final loaded = state.threads.value as ThreadsLoaded;
        expect(loaded.threads.length, 2);
        expect(loaded.threads.first.id, 'thread-2'); // newer first
        expect(loaded.threads.last.id, 'thread-1');

        state.dispose();
      },
    );

    test('ignores duplicate thread id', () async {
      final existing = ThreadInfo(
        id: 'thread-1',
        roomId: 'room-1',
        name: 'Existing',
        createdAt: DateTime(2026, 1, 1),
      );
      api.nextThreads = [existing];

      final state = ThreadListState(connection: connection, roomId: 'room-1');
      await Future<void>.delayed(Duration.zero);

      state.noteSpawnedThread(existing);

      final loaded = state.threads.value as ThreadsLoaded;
      expect(loaded.threads.length, 1);

      state.dispose();
    });

    test('from non-loaded state, defers to a fresh fetch instead of '
        'clobbering with a single-element list', () async {
      // Initial fetch fails: state ends up in ThreadsFailed.
      api.nextThreadsError = Exception('slow network');

      final state = ThreadListState(connection: connection, roomId: 'room-1');
      await Future<void>.delayed(Duration.zero);
      expect(state.threads.value, isA<ThreadsFailed>());

      // Now the server has the user's newly-created thread plus the
      // pre-existing ones. A subsequent fetch should bring them all in.
      final newThread = ThreadInfo(
        id: 'thread-1',
        roomId: 'room-1',
        name: 'New',
        createdAt: DateTime(2026, 3, 1),
      );
      final preExisting = ThreadInfo(
        id: 'thread-0',
        roomId: 'room-1',
        name: 'Pre-existing',
        createdAt: DateTime(2026, 1, 1),
      );
      api.nextThreadsError = null;
      api.nextThreads = [preExisting, newThread];

      state.noteSpawnedThread(newThread);
      // noteSpawnedThread does not transition to Loaded synchronously — it
      // schedules a fetch.
      expect(state.threads.value, isA<ThreadsLoading>());

      await Future<void>.delayed(Duration.zero);

      final loaded = state.threads.value as ThreadsLoaded;
      expect(loaded.threads.map((t) => t.id).toSet(), {'thread-0', 'thread-1'});

      state.dispose();
    });

    test('does nothing when disposed', () async {
      api.nextThreads = [];

      final state = ThreadListState(connection: connection, roomId: 'room-1');
      await Future<void>.delayed(Duration.zero);

      state.dispose();
      state.noteSpawnedThread(
        ThreadInfo(
          id: 'thread-1',
          roomId: 'room-1',
          name: 'New',
          createdAt: DateTime(2026, 3, 1),
        ),
      );

      final loaded = state.threads.value as ThreadsLoaded;
      expect(loaded.threads, isEmpty);
    });
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

    final state = ThreadListState(connection: connection, roomId: 'room-1');

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
