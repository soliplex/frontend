import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/inactivity_logout_storage.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_module.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_read_markers.dart';
import 'package:soliplex_frontend/src/modules/room/run_registry.dart';

import '../../helpers/fakes.dart';

ServerManager _createManager() => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

void main() {
  group('LobbyAppModule', () {
    test('contributes /lobby route', () {
      final contribution = LobbyAppModule(
        serverManager: _createManager(),
        identity: testIdentity(),
        registry: RunRegistry(),
        roomReadMarkers: RoomReadMarkers(),
        serverReadMarkers: ServerReadMarkers(),
        inactivityLogoutFlags: LocalInactivityLogoutFlagStorage(),
      ).build();
      final paths =
          contribution.routes.whereType<GoRoute>().map((r) => r.path).toList();
      expect(paths, contains('/lobby'));
    });

    test('does not contribute a redirect', () {
      final contribution = LobbyAppModule(
        serverManager: _createManager(),
        identity: testIdentity(),
        registry: RunRegistry(),
        roomReadMarkers: RoomReadMarkers(),
        serverReadMarkers: ServerReadMarkers(),
        inactivityLogoutFlags: LocalInactivityLogoutFlagStorage(),
      ).build();
      expect(contribution.redirect, isNull);
    });
  });
}
