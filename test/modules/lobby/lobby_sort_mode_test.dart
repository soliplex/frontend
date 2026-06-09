import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_sort_mode.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_state.dart';

import '../../helpers/fakes.dart';

ServerManager _createManager() => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

ThreadInfo _thread(String id, DateTime createdAt) =>
    ThreadInfo(id: id, roomId: 'room', createdAt: createdAt);

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
        'fetches each room\'s newest thread timestamp eagerly (so cards can '
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
        ..threadsByRoom['r1'] = [_thread('t1', older)]
        // Newest of several should win.
        ..threadsByRoom['r2'] = [_thread('t2', older), _thread('t3', newer)]
        // No threads → null timestamp.
        ..threadsByRoom['r3'] = const [];

      // Sorting stays at the default (none); activity is still fetched.
      final state = LobbyState(
        serverManager: manager,
        apiResolver: (_) => fakeApi,
      );
      // Two turns: one for getRooms, one for the getThreads sweep it triggers.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(state.sortMode.value, LobbySortMode.none);
      final activity = state.roomActivity.value;
      expect(activity[('local', 'r1')], older);
      expect(activity[('local', 'r2')], newer);
      expect(activity[('local', 'r3')], isNull);
      expect(activity.containsKey(('local', 'r3')), isTrue);
      expect(state.activityLoading.value, isFalse);
      state.dispose();
    });
  });
}
