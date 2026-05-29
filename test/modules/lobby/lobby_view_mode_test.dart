import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_state.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_view_mode.dart';

import '../../helpers/fakes.dart';

ServerManager _createManager() => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LobbyViewModeStorage', () {
    test('defaults to list when nothing is persisted', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await LobbyViewModeStorage.load(), LobbyViewMode.list);
    });

    test('round-trips the saved mode', () async {
      SharedPreferences.setMockInitialValues({});
      await LobbyViewModeStorage.save(LobbyViewMode.grid);
      expect(await LobbyViewModeStorage.load(), LobbyViewMode.grid);
    });

    test('falls back to list on an unrecognized stored value', () async {
      SharedPreferences.setMockInitialValues(
        {'soliplex_lobby_view_mode': 'bogus'},
      );
      expect(await LobbyViewModeStorage.load(), LobbyViewMode.list);
    });
  });

  group('LobbyState.viewMode', () {
    test('starts at list', () {
      SharedPreferences.setMockInitialValues({});
      final state = LobbyState(serverManager: _createManager());
      expect(state.viewMode.value, LobbyViewMode.list);
      state.dispose();
    });

    test('adopts the persisted mode after async load', () async {
      SharedPreferences.setMockInitialValues(
        {'soliplex_lobby_view_mode': 'grid'},
      );
      final state = LobbyState(serverManager: _createManager());
      await Future<void>.delayed(Duration.zero);
      expect(state.viewMode.value, LobbyViewMode.grid);
      state.dispose();
    });

    test('setViewMode updates the signal and persists the choice', () async {
      SharedPreferences.setMockInitialValues({});
      final state = LobbyState(serverManager: _createManager());
      await Future<void>.delayed(Duration.zero);

      state.setViewMode(LobbyViewMode.grid);

      expect(state.viewMode.value, LobbyViewMode.grid);
      expect(await LobbyViewModeStorage.load(), LobbyViewMode.grid);
      state.dispose();
    });
  });
}
