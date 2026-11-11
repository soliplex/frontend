import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;
import 'package:soliplex_client/soliplex_client.dart' show AuthException;
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
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
        h.api.allThreadsCalls.map((c) => (limit: c.limit, cursor: c.cursor)),
        equals([(limit: 2, cursor: null), (limit: 2, cursor: '2')]),
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
      final loaded = h.state.threads.value as GlobalThreadsLoaded;
      expect(loaded.loadingMore, isFalse);
      expect(loaded.threads.map((t) => t.id), ['a']);

      h.state.dispose();
    });

    test('a failed later page keeps the rows, and a retry resumes', () async {
      final h = _harness();
      h.api.allThreads = [_thread('a'), _thread('b'), _thread('c')];
      h.state.setServer(_serverId);
      await pumpEventQueue();

      h.api.nextAllThreadsError = Exception('blip');
      await h.state.loadMore();

      var loaded = h.state.threads.value as GlobalThreadsLoaded;
      expect(loaded.threads.map((t) => t.id), ['a', 'b']);
      expect(loaded.loadMoreError, isNotNull);
      expect(loaded.loadingMore, isFalse);
      expect(loaded.hasMore, isTrue);

      h.api.nextAllThreadsError = null;
      await h.state.loadMore();

      loaded = h.state.threads.value as GlobalThreadsLoaded;
      expect(loaded.threads.map((t) => t.id), ['a', 'b', 'c']);
      expect(loaded.loadMoreError, isNull);
      // The retry asked for the page that failed, not page one.
      expect(h.api.allThreadsCalls.map((c) => c.cursor), [null, '2', '2']);

      h.state.dispose();
    });

    test('a 404 on a later page is not an unsupported server', () async {
      final h = _harness();
      h.api.allThreads = [_thread('a'), _thread('b'), _thread('c')];
      h.state.setServer(_serverId);
      await pumpEventQueue();

      h.api.nextAllThreadsError = const NotFoundException(message: 'gone');
      await h.state.loadMore();

      final loaded = h.state.threads.value as GlobalThreadsLoaded;
      expect(loaded.loadMoreError, isA<NotFoundException>());
      expect(loaded.threads, hasLength(2));

      h.state.dispose();
    });

    test('loadMore refuses to overlap an in-flight page', () async {
      final h = _harness();
      h.api.allThreads = [_thread('a'), _thread('b'), _thread('c')];

      h.state.setServer(_serverId);
      await pumpEventQueue();

      // Hold the second page open, then ask twice more. Without the
      // in-flight guard both would fire with the same cursor and the page
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
      expect(h.api.allThreadsCalls.last.cursor, isNull);

      h.state.dispose();
    });

    test('an unlabeled filter refetches and counts as filtering', () async {
      final h = _harness();
      h.api.allThreads = [_thread('a')];
      h.state.setServer(_serverId);
      await pumpEventQueue();
      expect(h.state.isFiltered, isFalse);

      h.state.setFilter(labelIds: [3], unlabeled: true);
      await pumpEventQueue();
      expect(h.api.allThreadsCalls.last.unlabeled, isTrue);
      expect(h.api.allThreadsCalls.last.labelIds, equals([3]));
      expect(h.state.isFiltered, isTrue);

      // The same filter again is a no-op, like any other.
      final calls = h.api.getAllThreadsCallCount;
      h.state.setFilter(labelIds: [3], unlabeled: true);
      await pumpEventQueue();
      expect(h.api.getAllThreadsCallCount, equals(calls));

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

    test('rename folds the new name in without refetching', () async {
      final h = _harness(pageSize: 10);
      h.api.allThreads = [_thread('a'), _thread('b')];
      h.state.setServer(_serverId);
      await pumpEventQueue();
      final callsBefore = h.api.getAllThreadsCallCount;

      final reason = await h.state.rename(_thread('a'), 'Renamed');

      expect(reason, isNull);
      final loaded = h.state.threads.value as GlobalThreadsLoaded;
      expect(loaded.threads.first.name, equals('Renamed'));
      // No refetch: the backend commits after responding, so a listing
      // requested here could still report the old name.
      expect(h.api.getAllThreadsCallCount, equals(callsBefore));

      h.state.dispose();
    });

    test('rename keeps the thread where it was', () async {
      // Re-sorting on rename would yank the row out from under whoever
      // just renamed it.
      final h = _harness(pageSize: 10);
      h.api.allThreads = [_thread('a'), _thread('b')];
      h.state.setServer(_serverId);
      await pumpEventQueue();

      await h.state.rename(_thread('a'), 'zzz-last-alphabetically');

      final loaded = h.state.threads.value as GlobalThreadsLoaded;
      expect(loaded.threads.map((t) => t.id), equals(['a', 'b']));

      h.state.dispose();
    });

    test('rename resends the description rather than dropping it', () async {
      final h = _harness(pageSize: 10);
      final described = ThreadInfo(
        id: 'a',
        roomId: 'room-1',
        name: 'a',
        description: 'keep me',
        createdAt: DateTime.utc(2026),
      );
      h.api.allThreads = [described];
      h.state.setServer(_serverId);
      await pumpEventQueue();

      await h.state.rename(described, 'Renamed');

      // 'updateThreadMetadata' replaces the row wholesale, so omitting
      // the description would silently erase it.
      expect(h.api.lastUpdatedDescription, equals('keep me'));

      h.state.dispose();
    });

    test('delete drops the thread from the held list', () async {
      final h = _harness(pageSize: 10);
      h.api.allThreads = [_thread('a'), _thread('b')];
      h.state.setServer(_serverId);
      await pumpEventQueue();

      final reason = await h.state.delete(_thread('a'));

      expect(reason, isNull);
      final loaded = h.state.threads.value as GlobalThreadsLoaded;
      expect(loaded.threads.map((t) => t.id), equals(['b']));

      h.state.dispose();
    });

    test('a failed delete leaves the list alone', () async {
      final h = _harness(pageSize: 10);
      h.api.allThreads = [_thread('a'), _thread('b')];
      h.state.setServer(_serverId);
      await pumpEventQueue();
      h.api.nextDeleteThreadError = Exception('boom');

      final reason = await h.state.delete(_thread('a'));

      expect(reason, isNotNull);
      final loaded = h.state.threads.value as GlobalThreadsLoaded;
      expect(loaded.threads.map((t) => t.id), equals(['a', 'b']));

      h.state.dispose();
    });

    test('saveProperties writes metadata and labels together', () async {
      final h = _harness(pageSize: 10);
      h.api
        ..allThreads = [_thread('a')]
        ..labels = const [
          ThreadLabel(id: 1, name: 'Manuals', color: '#42D76D'),
        ];
      h.state.setServer(_serverId);
      await pumpEventQueue();

      final reason = await h.state.saveProperties(
        _thread('a'),
        name: 'Renamed',
        description: 'A description',
        labelIds: const [1],
      );

      expect(reason, isNull);
      expect(h.api.lastUpdatedName, equals('Renamed'));
      expect(h.api.setThreadLabelsCalls.single.labelIds, equals([1]));

      final loaded = h.state.threads.value as GlobalThreadsLoaded;
      final thread = loaded.threads.single;
      // The labels response carries no metadata, so the local copy takes
      // the names from what was sent and the labels from what came back.
      expect(thread.name, equals('Renamed'));
      expect(thread.description, equals('A description'));
      expect(thread.labels.single.name, equals('Manuals'));

      h.state.dispose();
    });

    test('explains a failed save rather than dumping the exception', () async {
      final h = _harness(pageSize: 10);
      h.api.allThreads = [_thread('a')];
      h.state.setServer(_serverId);
      await pumpEventQueue();
      h.api.nextUpdateMetadataError = Exception('boom');

      final reason = await h.state.saveProperties(
        _thread('a'),
        name: 'Renamed',
        description: '',
        labelIds: const [],
      );

      expect(reason, contains('Could not save'));
      expect(reason, isNot(contains('boom')));

      h.state.dispose();
    });

    test('refuses to mutate with no server selected', () async {
      final h = _harness();

      final reason = await h.state.rename(_thread('a'), 'Renamed');

      expect(reason, isNotNull);
      expect(h.api.updateMetadataCallCount, equals(0));

      h.state.dispose();
    });
  });

  group('GlobalThreadsState following the selection', () {
    test('loads whichever server is selected', () async {
      final h = _following();
      h.select(_a);
      await pumpEventQueue();
      expect(h.ids(), ['a1', 'a2']);

      h.select(_b);
      await pumpEventQueue();
      expect(h.ids(), ['b1', 'b2']);

      h.dispose();
    });

    test("a page from the old server never lands on the new one's", () async {
      final h = _following();
      final held = h.apiA.holdNext('getAllThreads');
      h.select(_a);
      h.select(_b);
      await pumpEventQueue();

      held.complete();
      await pumpEventQueue();

      expect(h.ids(), ['b1', 'b2']);
      h.dispose();
    });

    test('a server switch starts unfiltered', () async {
      final h = _following();
      h.select(_a);
      await pumpEventQueue();
      h.state
        ..setFilter(labelIds: [7], query: 'manual')
        ..searchText = '@bug manual';
      await pumpEventQueue();

      h.select(_b);
      await pumpEventQueue();

      // Label 7 on A is some other label, or none, on B.
      final call = h.apiB.allThreadsCalls.single;
      expect(call.labelIds, isEmpty);
      expect(call.query, isEmpty);
      expect(h.state.isFiltered, isFalse);
      expect(h.state.searchText, isEmpty);
      h.dispose();
    });

    test('a signed-out server is never asked for threads', () async {
      final h = _following(authA: _signedOut());
      h.select(_a);
      await pumpEventQueue();

      final state = h.state.threads.value as GlobalThreadsSignedOut;
      expect(state.expired, isFalse);
      expect(h.apiA.getAllThreadsCallCount, 0);
      h.dispose();
    });

    test('signing out drops the rows; signing in loads them again', () async {
      final h = _following();
      h.select(_a);
      await pumpEventQueue();

      h.authA.logout();
      expect(h.state.threads.value, isA<GlobalThreadsSignedOut>());

      _signIn(h.authA);
      await pumpEventQueue();
      expect(h.ids(), ['a1', 'a2']);
      h.dispose();
    });

    test('an expired session says so', () async {
      final h = _following();
      h.select(_a);
      await pumpEventQueue();

      h.authA.markSessionExpired();

      final state = h.state.threads.value as GlobalThreadsSignedOut;
      expect(state.expired, isTrue);
      h.dispose();
    });

    test('a rejected write sends the user to sign in again', () async {
      final h = _following();
      h.select(_a);
      await pumpEventQueue();
      h.apiA.nextUpdateMetadataError = const AuthException(message: '401');

      final reason = await h.state.rename(_thread('a1'), 'Renamed');

      expect(reason, isNotNull);
      expect(h.authA.session.value, isA<ExpiredSession>());
      h.dispose();
    });

    test('a null selection keeps the rows', () async {
      final h = _following();
      h.select(_a);
      await pumpEventQueue();

      h.selection.value = null;
      await pumpEventQueue();

      expect(h.ids(), ['a1', 'a2']);
      expect(h.apiA.getAllThreadsCallCount, 1);
      h.dispose();
    });

    test('removing the server empties the listing', () async {
      final h = _following();
      h.select(_a);
      await pumpEventQueue();

      h.servers.value = {_b: h.servers.value[_b]!};

      expect(h.ids(), isEmpty);
      expect(h.state.serverId, isNull);
      h.dispose();
    });

    test('following again keeps the pages and re-checks the first', () async {
      final h = _following(threadsA: ['a', 'b', 'c', 'd', 'e']);
      h.select(_a);
      await pumpEventQueue();
      await h.state.loadMore();
      expect(h.ids(), ['a', 'b', 'c', 'd']);

      // The screen goes away, and 'd' gets a reply meanwhile.
      h.unfollow();
      h.apiA.allThreads = [for (final id in 'dabce'.split('')) _thread(id)];

      // The screen comes back; its selection restores asynchronously.
      final seen = <GlobalThreads>[];
      final stop = h.state.threads.subscribe(seen.add);
      h.selection.value = null;
      h.refollow();
      h.select(_a);
      await pumpEventQueue();
      stop();

      expect(seen.whereType<GlobalThreadsLoading>(), isEmpty);
      expect(h.ids(), ['d', 'a', 'b', 'c']);
      expect(
        h.apiA.allThreadsCalls.map((c) => c.cursor),
        [null, '2', null],
      );

      // The held cursor still points past 'c'; 'd' doesn't come back.
      await h.state.loadMore();
      expect(h.ids(), ['d', 'a', 'b', 'c', 'e']);
      h.dispose();
    });

    test('a first page with nothing held in common replaces the rows',
        () async {
      final h = _following(threadsA: ['a', 'b', 'c', 'd']);
      h.select(_a);
      await pumpEventQueue();

      h.apiA.allThreads = [
        for (final id in ['n1', 'n2', 'n3', 'a', 'b']) _thread(id),
      ];
      await h.state.revalidate();

      // Threads between 'n2' and 'a' could be missing from both pages, so
      // the listing restarts from the fresh page instead.
      expect(h.ids(), ['n1', 'n2']);
      final loaded = h.state.threads.value as GlobalThreadsLoaded;
      expect(loaded.hasMore, isTrue);
      h.dispose();
    });

    test('a failed re-check keeps the rows', () async {
      final h = _following();
      h.select(_a);
      await pumpEventQueue();

      h.apiA.nextAllThreadsError = Exception('blip');
      await h.state.revalidate();

      expect(h.ids(), ['a1', 'a2']);
      h.dispose();
    });
  });
}

const _a = 'http://a:8000';
const _b = 'http://b:8000';

AuthSession _signedOut() =>
    AuthSession(refreshService: FakeTokenRefreshService());

void _signIn(AuthSession auth) => auth.login(
      provider: const OidcProvider(
        discoveryUrl: 'https://idp.test/.well-known/openid-configuration',
        clientId: 'client',
      ),
      tokens: AuthTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );

/// A listing following a selection across two servers that require
/// sign-in, each with its own fake API.
({
  GlobalThreadsState state,
  FakeSoliplexApi apiA,
  FakeSoliplexApi apiB,
  AuthSession authA,
  Signal<String?> selection,
  Signal<Map<String, ServerEntry>> servers,
  void Function(String id) select,
  List<String> Function() ids,
  void Function() unfollow,
  void Function() refollow,
  void Function() dispose,
}) _following({
  AuthSession? authA,
  List<String> threadsA = const ['a1', 'a2'],
}) {
  final apiA = FakeSoliplexApi()
    ..allThreads = [for (final id in threadsA) _thread(id)];
  final apiB = FakeSoliplexApi()..allThreads = [_thread('b1'), _thread('b2')];
  final sessionA = authA ?? authInActiveSession();
  final servers = Signal<Map<String, ServerEntry>>({
    _a: createTestServerEntry(
      api: apiA,
      serverId: _a,
      alias: 'a',
      requiresAuth: true,
      auth: sessionA,
    ),
    _b: createTestServerEntry(
      api: apiB,
      serverId: _b,
      alias: 'b',
      requiresAuth: true,
      auth: authInActiveSession(),
    ),
  });
  final selection = Signal<String?>(null);
  final state = GlobalThreadsState(
    entryResolver: (id) => servers.value[id],
    pageSize: 2,
  );
  var unfollow = state.follow(selection: selection, servers: servers);

  return (
    state: state,
    apiA: apiA,
    apiB: apiB,
    authA: sessionA,
    selection: selection,
    servers: servers,
    select: (id) => selection.value = id,
    ids: () => switch (state.threads.value) {
          GlobalThreadsLoaded(:final threads) => [
              for (final thread in threads) thread.id,
            ],
          _ => const <String>[],
        },
    unfollow: () => unfollow(),
    refollow: () =>
        unfollow = state.follow(selection: selection, servers: servers),
    dispose: () {
      unfollow();
      state.dispose();
    },
  );
}
