import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';
import 'package:soliplex_frontend/src/modules/lobby/global_threads_state.dart';

import '../../helpers/fakes.dart';
import '../../helpers/test_server_entry.dart';

const _serverId = 'http://test-server:8000';

ThreadInfo _thread(String id, {String roomId = 'room-1'}) => ThreadInfo(
      id: id,
      roomId: roomId,
      name: id,
      createdAt: DateTime.utc(2026),
    );

/// Builds a controller wired to a single fake server.
({GlobalThreadsState state, FakeSoliplexApi api}) _harness({
  int pageSize = 2,
  ServerEntry? entry,
}) {
  final api = FakeSoliplexApi();
  final serverEntry = entry ?? createTestServerEntry(api: api);
  final state = GlobalThreadsState(
    entryResolver: (id) => id == _serverId ? serverEntry : null,
    pageSize: pageSize,
  );
  return (state: state, api: api);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GlobalThreadsState', () {
    test('starts loading and resolves to the first page', () async {
      final h = _harness();
      h.api.allThreads = [_thread('a'), _thread('b'), _thread('c')];

      expect(h.state.threads.value, isA<GlobalThreadsLoading>());

      h.state.setServer(_serverId);
      await pumpEventQueue();

      final loaded = h.state.threads.value as GlobalThreadsLoaded;
      expect(loaded.threads.map((t) => t.id), equals(['a', 'b']));
      expect(loaded.hasMore, isTrue);
      expect(loaded.loadingMore, isFalse);

      h.state.dispose();
    });

    test('loadMore appends the next page without refetching the first',
        () async {
      final h = _harness();
      h.api.allThreads = [_thread('a'), _thread('b'), _thread('c')];

      h.state.setServer(_serverId);
      await pumpEventQueue();
      await h.state.loadMore();

      final loaded = h.state.threads.value as GlobalThreadsLoaded;
      expect(loaded.threads.map((t) => t.id), equals(['a', 'b', 'c']));
      expect(loaded.hasMore, isFalse);
      expect(
        h.api.allThreadsCalls.map((c) => (limit: c.limit, offset: c.offset)),
        equals([(limit: 2, offset: 0), (limit: 2, offset: 2)]),
      );

      h.state.dispose();
    });

    test('loadMore is a no-op once the last page has arrived', () async {
      final h = _harness(pageSize: 5);
      h.api.allThreads = [_thread('a')];

      h.state.setServer(_serverId);
      await pumpEventQueue();
      await h.state.loadMore();

      // One page covered everything, so there is nothing more to ask for.
      expect(h.api.getAllThreadsCallCount, equals(1));

      h.state.dispose();
    });

    test('loadMore refuses to overlap an in-flight page', () async {
      final h = _harness();
      h.api.allThreads = [_thread('a'), _thread('b'), _thread('c')];

      h.state.setServer(_serverId);
      await pumpEventQueue();

      // Hold the second page open, then ask twice more. Without the
      // in-flight guard both would fire at the same offset and the page
      // would be appended twice.
      final gate = Completer<void>();
      h.api.allThreadsGate = gate;

      final first = h.state.loadMore();
      final second = h.state.loadMore();
      gate.complete();
      await Future.wait([first, second]);

      final loaded = h.state.threads.value as GlobalThreadsLoaded;
      expect(loaded.threads.map((t) => t.id), equals(['a', 'b', 'c']));
      expect(h.api.getAllThreadsCallCount, equals(2));

      h.state.dispose();
    });

    test('marks loadingMore while the next page is in flight', () async {
      final h = _harness();
      h.api.allThreads = [_thread('a'), _thread('b'), _thread('c')];

      h.state.setServer(_serverId);
      await pumpEventQueue();

      final gate = Completer<void>();
      h.api.allThreadsGate = gate;
      final pending = h.state.loadMore();

      final mid = h.state.threads.value as GlobalThreadsLoaded;
      // The already-fetched rows stay on screen rather than blanking.
      expect(mid.threads.map((t) => t.id), equals(['a', 'b']));
      expect(mid.loadingMore, isTrue);

      gate.complete();
      await pending;

      h.state.dispose();
    });

    test('refresh restarts from the first page', () async {
      final h = _harness();
      h.api.allThreads = [_thread('a'), _thread('b'), _thread('c')];

      h.state.setServer(_serverId);
      await pumpEventQueue();
      await h.state.loadMore();

      h.api.allThreads = [_thread('z')];
      await h.state.refresh();

      final loaded = h.state.threads.value as GlobalThreadsLoaded;
      expect(loaded.threads.map((t) => t.id), equals(['z']));
      expect(h.api.allThreadsCalls.last.limit, equals(2));
      expect(h.api.allThreadsCalls.last.offset, equals(0));

      h.state.dispose();
    });

    test('switching servers discards the previous listing', () async {
      final h = _harness();
      h.api.allThreads = [_thread('a'), _thread('b'), _thread('c')];

      h.state.setServer(_serverId);
      await pumpEventQueue();

      // An unknown server resolves to no entry, so the listing empties
      // rather than keeping the old server's threads under a new heading.
      h.state.setServer('http://other:8000');
      await pumpEventQueue();

      final loaded = h.state.threads.value as GlobalThreadsLoaded;
      expect(loaded.threads, isEmpty);

      h.state.dispose();
    });

    test('re-selecting the same server does not restart paging', () async {
      final h = _harness();
      h.api.allThreads = [_thread('a'), _thread('b'), _thread('c')];

      h.state.setServer(_serverId);
      await pumpEventQueue();
      await h.state.loadMore();
      h.state.setServer(_serverId);
      await pumpEventQueue();

      // Still the accumulated pages, and no extra request.
      final loaded = h.state.threads.value as GlobalThreadsLoaded;
      expect(loaded.threads.length, equals(3));
      expect(h.api.getAllThreadsCallCount, equals(2));

      h.state.dispose();
    });

    test('clearing the server empties the listing', () async {
      final h = _harness();
      h.api.allThreads = [_thread('a')];

      h.state.setServer(_serverId);
      await pumpEventQueue();
      h.state.setServer(null);
      await pumpEventQueue();

      final loaded = h.state.threads.value as GlobalThreadsLoaded;
      expect(loaded.threads, isEmpty);
      expect(loaded.hasMore, isFalse);

      h.state.dispose();
    });

    test('a 404 reports an unsupported server, not a failure', () async {
      final h = _harness();
      h.api.nextAllThreadsError = const NotFoundException(message: 'no route');

      h.state.setServer(_serverId);
      await pumpEventQueue();

      // An older backend has no such endpoint; offering a retry would
      // just 404 again, so this is a distinct state from a fault.
      expect(h.state.threads.value, isA<GlobalThreadsUnsupported>());

      h.state.dispose();
    });

    test('other errors surface as a failure', () async {
      final h = _harness();
      h.api.nextAllThreadsError = Exception('boom');

      h.state.setServer(_serverId);
      await pumpEventQueue();

      expect(h.state.threads.value, isA<GlobalThreadsFailed>());

      h.state.dispose();
    });

    test('a page arriving after dispose is discarded', () async {
      final h = _harness();
      h.api.allThreads = [_thread('a'), _thread('b'), _thread('c')];

      final gate = Completer<void>();
      h.api.allThreadsGate = gate;
      h.state.setServer(_serverId);

      h.state.dispose();
      gate.complete();
      await pumpEventQueue();

      // Never reaches Loaded: writing after teardown would resurrect a
      // disposed controller's state.
      expect(h.state.threads.value, isA<GlobalThreadsLoading>());
    });

    test('an unknown server yields an empty listing', () async {
      final h = _harness();

      h.state.setServer('http://nowhere:8000');
      await pumpEventQueue();

      final loaded = h.state.threads.value as GlobalThreadsLoaded;
      expect(loaded.threads, isEmpty);
      expect(h.api.getAllThreadsCallCount, equals(0));

      h.state.dispose();
    });
  });
}
