import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_module.dart';

import '../../helpers/fakes.dart';

ServerManager _createManager() => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

void main() {
  group('LobbyAppModule', () {
    test('contributes /lobby route', () {
      final contribution =
          LobbyAppModule(serverManager: _createManager()).build();
      final paths =
          contribution.routes.whereType<GoRoute>().map((r) => r.path).toList();
      expect(paths, contains('/lobby'));
    });

    test('does not contribute a redirect', () {
      final contribution =
          LobbyAppModule(serverManager: _createManager()).build();
      expect(contribution.redirect, isNull);
    });
  });
}
