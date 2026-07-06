import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;
import 'package:soliplex_client/soliplex_client.dart'
    show AuthException, NotFoundException, PermissionDeniedException;
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_sort_mode.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_state.dart';

import '../../helpers/fakes.dart';

ServerManager _createManager() => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

RoomStats _stats(DateTime? lastActivity) =>
    RoomStats(lastActivity: lastActivity);

/// Drains pending microtasks. Over-pumps rather than coupling to the exact
/// number of async hops the state machine takes to settle.
Future<void> _settle([int turns = 12]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('LobbySortModeStorage', () {
    test('defaults to none when nothing is persisted', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await LobbySortModeStorage.load(), LobbySortMode.none);
    });

    test('round-trips the saved mode', () async {
      SharedPreferences.setMockInitialValues({});
      await LobbySortModeStorage.save(LobbySortMode.recentActivity);
      expect(await LobbySortModeStorage.load(), LobbySortMode.recentActivity);
    });

    test('falls back to none on an unrecognized stored value', () async {
      SharedPreferences.setMockInitialValues(
        {'soliplex_lobby_sort_mode': 'bogus'},
      );
      expect(await LobbySortModeStorage.load(), LobbySortMode.none);
    });

    test('round-trips unreadFirst', () async {
      SharedPreferences.setMockInitialValues({});
      await LobbySortModeStorage.save(LobbySortMode.unreadFirst);
      expect(await LobbySortModeStorage.load(), LobbySortMode.unreadFirst);
    });
  });

  group('LobbyState sorting', () {
    test('starts at none and adopts the persisted mode after async load',
        () async {
      SharedPreferences.setMockInitialValues(
        {'soliplex_lobby_sort_mode': 'recentActivity'},
      );
      final state = LobbyState(serverManager: _createManager());
      expect(state.sortMode.value, LobbySortMode.none);
      await Future<void>.delayed(Duration.zero);
      expect(state.sortMode.value, LobbySortMode.recentActivity);
      state.dispose();
    });

    test('setSortMode updates the signal and persists the choice', () async {
      final state = LobbyState(serverManager: _createManager());
      await Future<void>.delayed(Duration.zero);

      state.setSortMode(LobbySortMode.recentActivity);
      expect(state.sortMode.value, LobbySortMode.recentActivity);
      expect(
        await LobbySortModeStorage.load(),
        LobbySortMode.recentActivity,
      );
      state.dispose();
    });

    test(
        'fetches each room\'s last-activity timestamp eagerly (so cards can '
        'show it), even with sorting at none', () async {
      final manager = _createManager();
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );

      final older = DateTime.utc(2026, 1, 1);
      final newer = DateTime.utc(2026, 6, 1);
      final fakeApi = FakeSoliplexApi()
        ..nextRooms = const [
          Room(id: 'r1', name: 'General'),
          Room(id: 'r2', name: 'Random'),
          Room(id: 'r3', name: 'Empty'),
        ]
        ..roomsStats = {
          'r1': _stats(older),
          'r2': _stats(newer),
          // No activity → null timestamp.
          'r3': _stats(null),
        };

      // Sorting stays at the default (none); activity is still fetched.
      final state = LobbyState(
        serverManager: manager,
        apiResolver: (_) => fakeApi,
      );
      // Two turns: one for getRooms, one for the activity batch it triggers.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(state.sortMode.value, LobbySortMode.none);
      final activity = state.roomActivity.value;
      expect(activity[(serverId: 'local', roomId: 'r1')], older);
      expect(activity[(serverId: 'local', roomId: 'r2')], newer);
      expect(activity[(serverId: 'local', roomId: 'r3')], isNull);
      expect(activity.containsKey((serverId: 'local', roomId: 'r3')), isTrue);
      expect(state.activityLoading.value, isFalse);
      state.dispose();
    });

    test(
        'clears the activity-loading flag when a reconcile cannot fetch '
        '(no stuck spinner)', () async {
      SharedPreferences.setMockInitialValues(
        {'soliplex_lobby_sort_mode': 'recentActivity'},
      );
      final manager = _createManager();
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );
      final gate = Completer<void>();
      final fakeApi = FakeSoliplexApi()
        ..nextRooms = const [Room(id: 'r1', name: 'General')]
        ..roomsStats = {'r1': _stats(DateTime.utc(2026))}
        ..roomsStatsGate = gate;

      final state =
          LobbyState(serverManager: manager, apiResolver: (_) => fakeApi);
      // Let rooms load and the batch start; it then parks on the gate.
      for (var i = 0; i < 12 && !state.activityLoading.value; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(state.activityLoading.value, isTrue,
          reason: 'the batch should be in flight, held open by the gate');

      // Removing the only server drops the selection to null, so the reconcile
      // it triggers hits an early return. The flag must still clear.
      manager.removeServer('local');
      expect(state.selectedServerId.value, isNull);
      expect(state.activityLoading.value, isFalse);

      gate.complete();
      await _settle();
      state.dispose();
    });

    test(
        'refetching a server recomputes its activity and leaves other '
        "servers' cached activity intact", () async {
      final manager = _createManager();
      manager.addServer(
        serverId: 'a',
        serverUrl: Uri.parse('http://a'),
        requiresAuth: false,
      );
      manager.addServer(
        serverId: 'b',
        serverUrl: Uri.parse('http://b'),
        requiresAuth: false,
      );

      final stale = DateTime.utc(2026, 1, 1);
      final other = DateTime.utc(2026, 3, 1);
      final fresh = DateTime.utc(2026, 6, 1);
      final apiA = FakeSoliplexApi()
        ..nextRooms = const [Room(id: 'ra', name: 'A-Room')]
        ..roomsStats = {'ra': _stats(stale)};
      final apiB = FakeSoliplexApi()
        ..nextRooms = const [Room(id: 'rb', name: 'B-Room')]
        ..roomsStats = {'rb': _stats(other)};

      final state = LobbyState(
        serverManager: manager,
        apiResolver: (entry) => entry.serverUrl.host == 'a' ? apiA : apiB,
      );
      await _settle();
      // Activity is fetched only for the selected server, so visit 'b' to
      // populate its cache, then return to 'a'.
      state.selectServer('b');
      await _settle();
      state.selectServer('a');
      await _settle();
      expect(state.roomActivity.value[(serverId: 'a', roomId: 'ra')], stale);
      expect(state.roomActivity.value[(serverId: 'b', roomId: 'rb')], other);

      // Change 'a's last-activity time and refetch only 'a'.
      apiA.roomsStats = {'ra': _stats(fresh)};
      state.refresh('a');
      await _settle();

      expect(state.roomActivity.value[(serverId: 'a', roomId: 'ra')], fresh,
          reason: "a refetch must recompute the refreshed server's activity");
      expect(state.roomActivity.value[(serverId: 'b', roomId: 'rb')], other,
          reason: "other servers' cached activity must survive");
      state.dispose();
    });

    test(
        'refreshing while the activity batch is in flight cancels it and '
        'starts a fresh fetch (does not coalesce onto the stale batch)',
        () async {
      final manager = _createManager();
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );
      final gate = Completer<void>();
      final fakeApi = FakeSoliplexApi()
        ..nextRooms = const [Room(id: 'r1', name: 'One')]
        ..roomsStats = {'r1': _stats(DateTime.utc(2026, 6))}
        ..roomsStatsGate = gate;

      final state =
          LobbyState(serverManager: manager, apiResolver: (_) => fakeApi);
      // Let the first activity batch start and park on the gate.
      for (var i = 0; i < 12 && !state.activityLoading.value; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(state.activityLoading.value, isTrue);
      expect(fakeApi.getRoomsStatsCallCount, 1);

      // Refresh while the batch is still in flight. _fetchRooms must cancel the
      // in-flight batch so the post-refresh reconcile starts a fresh fetch
      // rather than being short-circuited by the coalesce guard.
      state.refresh('local');
      await _settle();
      expect(fakeApi.getRoomsStatsCallCount, 2,
          reason: 'a mid-batch refresh must start a new fetch, not coalesce '
              'onto the stale one');

      // Release both batches; the first (cancelled) is dropped, the second
      // writes the activity.
      gate.complete();
      await _settle();
      expect(state.roomActivity.value[(serverId: 'local', roomId: 'r1')],
          DateTime.utc(2026, 6));
      state.dispose();
    });

    test(
        'a persistent failure (pre-stats 404) null-fills every room and is '
        'not retried', () async {
      final manager = _createManager();
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );
      final fakeApi = FakeSoliplexApi()
        ..nextRooms = const [
          Room(id: 'r1', name: 'One'),
          Room(id: 'r2', name: 'Two'),
        ]
        ..nextRoomsStatsError = const NotFoundException(message: 'no stats');

      final state =
          LobbyState(serverManager: manager, apiResolver: (_) => fakeApi);
      await _settle();

      final activity = state.roomActivity.value;
      expect(activity[(serverId: 'local', roomId: 'r1')], isNull);
      expect(activity[(serverId: 'local', roomId: 'r2')], isNull);
      expect(activity.containsKey((serverId: 'local', roomId: 'r1')), isTrue,
          reason: 'a 404 records rooms as fetched (null), so it is not '
              're-swept');
      expect(activity.containsKey((serverId: 'local', roomId: 'r2')), isTrue);

      // The null-fill must keep a persistently-failing batch (a pre-stats
      // backend's 404) out of the "missing" set, so a later reconcile does not
      // re-fire it.
      final callsAfterFirst = fakeApi.getRoomsStatsCallCount;
      state.setSortMode(LobbySortMode.recentActivity);
      await _settle();
      expect(fakeApi.getRoomsStatsCallCount, callsAfterFirst,
          reason: 'a stable failure must not be retried on every reconcile');
      state.dispose();
    });

    test(
        'a transient failure leaves rooms unfetched so the next reconcile '
        'retries', () async {
      final manager = _createManager();
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );
      final fakeApi = FakeSoliplexApi()
        ..nextRooms = const [Room(id: 'r1', name: 'One')]
        ..nextRoomsStatsError = Exception('network blip');

      final state =
          LobbyState(serverManager: manager, apiResolver: (_) => fakeApi);
      await _settle();

      // A transient failure (network/5xx/decode) must not be cached as "no
      // activity": leaving the room absent lets a later reconcile retry,
      // rather than freezing the lobby on no activity with no recovery cue.
      expect(
        state.roomActivity.value.containsKey((serverId: 'local', roomId: 'r1')),
        isFalse,
        reason: 'a transient failure leaves the room unfetched',
      );

      // Recover, then trigger a reconcile: the still-missing room is refetched.
      fakeApi
        ..nextRoomsStatsError = null
        ..roomsStats = {'r1': _stats(DateTime.utc(2026, 6))};
      final callsAfterFirst = fakeApi.getRoomsStatsCallCount;
      state.setSortMode(LobbySortMode.recentActivity);
      await _settle();
      expect(fakeApi.getRoomsStatsCallCount, greaterThan(callsAfterFirst),
          reason: 'a transient failure must be retried on the next reconcile');
      expect(state.roomActivity.value[(serverId: 'local', roomId: 'r1')],
          DateTime.utc(2026, 6),
          reason: 'the retry populates the recovered activity');
      state.dispose();
    });

    test('a displayed room the batch omits caches null and is not re-fetched',
        () async {
      final manager = _createManager();
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );
      final fakeApi = FakeSoliplexApi()
        ..nextRooms = const [
          Room(id: 'r1', name: 'One'),
          Room(id: 'r2', name: 'Two'),
        ]
        // Authz skew: the batch omits r2 (it's displayed but not returned).
        ..roomsStats = {'r1': _stats(DateTime.utc(2026, 6))};

      final state =
          LobbyState(serverManager: manager, apiResolver: (_) => fakeApi);
      await _settle();

      expect(
          state.roomActivity.value[(serverId: 'local', roomId: 'r2')], isNull);
      expect(
        state.roomActivity.value.containsKey((serverId: 'local', roomId: 'r2')),
        isTrue,
        reason: 'an omitted room is recorded as fetched-with-no-activity',
      );
      final callsAfterFirst = fakeApi.getRoomsStatsCallCount;

      // Toggling sort triggers a reconcile; the omitted room must not re-fire
      // the batch (the null-fill keeps it out of the "missing" set).
      state.setSortMode(LobbySortMode.recentActivity);
      await _settle();
      expect(fakeApi.getRoomsStatsCallCount, callsAfterFirst,
          reason: 'an omitted room must not re-trigger the batch');
      state.dispose();
    });

    test(
        'repeat reconciles while a batch is in flight issue exactly one '
        'request and keep the spinner on', () async {
      final manager = _createManager();
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );
      final gate = Completer<void>();
      final fakeApi = FakeSoliplexApi()
        ..nextRooms = const [Room(id: 'r1', name: 'One')]
        ..roomsStats = {'r1': _stats(DateTime.utc(2026, 6))}
        ..roomsStatsGate = gate;

      final state =
          LobbyState(serverManager: manager, apiResolver: (_) => fakeApi);
      for (var i = 0; i < 12 && !state.activityLoading.value; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(state.activityLoading.value, isTrue);
      expect(fakeApi.getRoomsStatsCallCount, 1);

      // Fire repeat reconciles for the same server while the batch is gated.
      state.setSortMode(LobbySortMode.recentActivity);
      state.setSortMode(LobbySortMode.none);
      await _settle();
      expect(fakeApi.getRoomsStatsCallCount, 1,
          reason: 'an in-flight batch must coalesce repeat reconciles');
      expect(state.activityLoading.value, isTrue,
          reason: 'the coalesce guard must not kill the spinner mid-fetch');

      gate.complete();
      await _settle();
      expect(state.activityLoading.value, isFalse);
      state.dispose();
    });

    test('removing the in-flight server then re-adding it re-fetches activity',
        () async {
      final manager = _createManager();
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );
      final gate = Completer<void>();
      final fakeApi = FakeSoliplexApi()
        ..nextRooms = const [Room(id: 'r1', name: 'One')]
        ..roomsStats = {'r1': _stats(DateTime.utc(2026, 6))}
        ..roomsStatsGate = gate;

      final state =
          LobbyState(serverManager: manager, apiResolver: (_) => fakeApi);
      for (var i = 0; i < 12 && !state.activityLoading.value; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(state.activityLoading.value, isTrue);

      // Remove the server whose batch is in flight, then release the now-orphan
      // request (its cancelled token must drop the result).
      manager.removeServer('local');
      gate.complete();
      await _settle();

      // Re-add the same id; its activity must fetch again rather than being
      // blocked forever by a stuck _activityFetchServerId.
      fakeApi.roomsStatsGate = null;
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );
      await _settle();

      expect(state.roomActivity.value[(serverId: 'local', roomId: 'r1')],
          DateTime.utc(2026, 6),
          reason: 're-added server must re-fetch activity');
      state.dispose();
    });

    test(
        'an AuthException during the batch funnels to session expiry, like the '
        'room-list and profile fetches', () async {
      final manager = _createManager();
      final entry = manager.addServer(
        serverId: 'auth',
        serverUrl: Uri.parse('https://api.example.com'),
      );
      entry.auth.login(
        provider: const OidcProvider(
          discoveryUrl: 'https://sso/.well-known/openid-configuration',
          clientId: 'c',
        ),
        tokens: AuthTokens(
          accessToken: 'a',
          refreshToken: 'r',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
      final fakeApi = FakeSoliplexApi()
        ..nextRooms = const [Room(id: 'r1', name: 'General')]
        ..nextRoomsStatsError = const AuthException(message: 'expired');

      final state =
          LobbyState(serverManager: manager, apiResolver: (_) => fakeApi);
      await _settle();

      expect(entry.auth.session.value, isA<ExpiredSession>(),
          reason: 'a batch AuthException must drive session expiry rather '
              'than being swallowed as a warning');
      state.dispose();
    });

    test(
        'a PermissionDeniedException during the batch null-fills without '
        'expiring the session', () async {
      final manager = _createManager();
      final entry = manager.addServer(
        serverId: 'authz',
        serverUrl: Uri.parse('https://api.example.com'),
      );
      entry.auth.login(
        provider: const OidcProvider(
          discoveryUrl: 'https://sso/.well-known/openid-configuration',
          clientId: 'c',
        ),
        tokens: AuthTokens(
          accessToken: 'a',
          refreshToken: 'r',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
      final fakeApi = FakeSoliplexApi()
        ..nextRooms = const [Room(id: 'r1', name: 'General')]
        ..nextRoomsStatsError =
            const PermissionDeniedException(message: 'forbidden');

      final state =
          LobbyState(serverManager: manager, apiResolver: (_) => fakeApi);
      await _settle();

      expect(entry.auth.session.value, isNot(isA<ExpiredSession>()),
          reason: 'a denied stats fetch is an expected per-server state, not '
              'a session expiry');
      expect(
          state.roomActivity.value[(serverId: 'authz', roomId: 'r1')], isNull);
      expect(
          state.roomActivity.value
              .containsKey((serverId: 'authz', roomId: 'r1')),
          isTrue,
          reason: 'a denied batch records rooms as fetched (null) so it is not '
              'retried on every reconcile');
      state.dispose();
    });

    test('a batch superseded by a selection change discards its stale results',
        () async {
      final manager = _createManager();
      manager.addServer(
        serverId: 'a',
        serverUrl: Uri.parse('http://a'),
        requiresAuth: false,
      );
      manager.addServer(
        serverId: 'b',
        serverUrl: Uri.parse('http://b'),
        requiresAuth: false,
      );
      final gateA = Completer<void>();
      final apiA = FakeSoliplexApi()
        ..nextRooms = const [Room(id: 'ra', name: 'A-Room')]
        ..roomsStats = {'ra': _stats(DateTime.utc(2026, 1))}
        ..roomsStatsGate = gateA;
      final apiB = FakeSoliplexApi()
        ..nextRooms = const [Room(id: 'rb', name: 'B-Room')]
        ..roomsStats = {'rb': _stats(DateTime.utc(2026, 6))};

      final state = LobbyState(
        serverManager: manager,
        apiResolver: (entry) => entry.serverUrl.host == 'a' ? apiA : apiB,
      );
      // 'a' is the initial selection; let its batch start and park on the gate.
      for (var i = 0; i < 12 && !state.activityLoading.value; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(state.activityLoading.value, isTrue,
          reason: "'a's batch should be in flight, held open by the gate");

      // Switching to 'b' cancels 'a's token and runs 'b's batch to completion.
      state.selectServer('b');
      await _settle();
      expect(state.roomActivity.value[(serverId: 'b', roomId: 'rb')],
          DateTime.utc(2026, 6));

      // Release 'a's now-cancelled batch; the isCancelled guard must drop its
      // result rather than writing it over the current selection's state.
      gateA.complete();
      await _settle();
      expect(
        state.roomActivity.value.containsKey((serverId: 'a', roomId: 'ra')),
        isFalse,
        reason: 'a batch cancelled by a selection change must not write its '
            'stale results',
      );
      state.dispose();
    });
  });
}
