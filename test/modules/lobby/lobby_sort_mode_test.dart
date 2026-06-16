import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;
import 'package:soliplex_client/soliplex_client.dart' show AuthException;
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

RoomStats _stats(String roomId, DateTime? lastMessageAt) =>
    RoomStats(roomId: roomId, lastMessageAt: lastMessageAt);

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
        'fetches each room\'s last-message timestamp eagerly (so cards can '
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
        ..statsByRoom['r1'] = _stats('r1', older)
        ..statsByRoom['r2'] = _stats('r2', newer)
        // No activity → null timestamp.
        ..statsByRoom['r3'] = _stats('r3', null);

      // Sorting stays at the default (none); activity is still fetched.
      final state = LobbyState(
        serverManager: manager,
        apiResolver: (_) => fakeApi,
      );
      // Two turns: one for getRooms, one for the getRoomStats sweep it triggers.
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
        ..statsByRoom['r1'] = _stats('r1', DateTime.utc(2026))
        ..statsGate = gate;

      final state =
          LobbyState(serverManager: manager, apiResolver: (_) => fakeApi);
      // Let rooms load and the sweep start; it then parks on the gate.
      for (var i = 0; i < 12 && !state.activityLoading.value; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(state.activityLoading.value, isTrue,
          reason: 'the sweep should be in flight, held open by the gate');

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
        ..statsByRoom['ra'] = _stats('ra', stale);
      final apiB = FakeSoliplexApi()
        ..nextRooms = const [Room(id: 'rb', name: 'B-Room')]
        ..statsByRoom['rb'] = _stats('rb', other);

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

      // Change 'a's last-message time and refetch only 'a'.
      apiA.statsByRoom['ra'] = _stats('ra', fresh);
      state.refresh('a');
      await _settle();

      expect(state.roomActivity.value[(serverId: 'a', roomId: 'ra')], fresh,
          reason: "a refetch must recompute the refreshed server's activity");
      expect(state.roomActivity.value[(serverId: 'b', roomId: 'rb')], other,
          reason: "other servers' cached activity must survive");
      state.dispose();
    });

    test('a room whose stats fetch fails records a null timestamp', () async {
      final manager = _createManager();
      manager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );
      final ok = DateTime.utc(2026, 6, 1);
      final fakeApi = FakeSoliplexApi()
        ..nextRooms = const [
          Room(id: 'ok', name: 'Ok'),
          Room(id: 'bad', name: 'Bad'),
        ]
        ..statsByRoom['ok'] = _stats('ok', ok)
        ..statsErrorByRoom['bad'] = Exception('stats fetch boom');

      final state =
          LobbyState(serverManager: manager, apiResolver: (_) => fakeApi);
      await _settle();

      final activity = state.roomActivity.value;
      expect(activity[(serverId: 'local', roomId: 'ok')], ok);
      expect(activity[(serverId: 'local', roomId: 'bad')], isNull,
          reason: 'a failed stats fetch maps to a null timestamp');
      expect(activity.containsKey((serverId: 'local', roomId: 'bad')), isTrue,
          reason: 'the failed room is recorded as fetched, so it is not '
              're-swept');
      state.dispose();
    });

    test(
        'an AuthException during the sweep funnels to session expiry, like the '
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
        ..statsErrorByRoom['r1'] = const AuthException(message: 'expired');

      final state =
          LobbyState(serverManager: manager, apiResolver: (_) => fakeApi);
      await _settle();

      expect(entry.auth.session.value, isA<ExpiredSession>(),
          reason: 'a swept-room AuthException must drive session expiry rather '
              'than being swallowed as a per-room warning');
      state.dispose();
    });

    test('a sweep superseded by a selection change discards its stale results',
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
        ..statsByRoom['ra'] = _stats('ra', DateTime.utc(2026, 1))
        ..statsGate = gateA;
      final apiB = FakeSoliplexApi()
        ..nextRooms = const [Room(id: 'rb', name: 'B-Room')]
        ..statsByRoom['rb'] = _stats('rb', DateTime.utc(2026, 6));

      final state = LobbyState(
        serverManager: manager,
        apiResolver: (entry) => entry.serverUrl.host == 'a' ? apiA : apiB,
      );
      // 'a' is the initial selection; let its sweep start and park on the gate.
      for (var i = 0; i < 12 && !state.activityLoading.value; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(state.activityLoading.value, isTrue,
          reason: "'a's sweep should be in flight, held open by the gate");

      // Switching to 'b' cancels 'a's token and runs 'b's sweep to completion.
      state.selectServer('b');
      await _settle();
      expect(state.roomActivity.value[(serverId: 'b', roomId: 'rb')],
          DateTime.utc(2026, 6));

      // Release 'a's now-cancelled sweep; the isCancelled guard must drop its
      // result rather than writing it over the current selection's state.
      gateA.complete();
      await _settle();
      expect(
        state.roomActivity.value.containsKey((serverId: 'a', roomId: 'ra')),
        isFalse,
        reason: 'a sweep cancelled by a selection change must not write its '
            'stale results',
      );
      state.dispose();
    });
  });
}
