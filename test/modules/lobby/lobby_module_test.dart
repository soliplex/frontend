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
  group('lobbyModule', () {
    test('contributes /lobby route', () {
      final contribution = lobbyModule(serverManager: _createManager());

      final paths =
          contribution.routes.whereType<GoRoute>().map((r) => r.path).toList();
      expect(paths, contains('/lobby'));
    });

    test('does not contribute a redirect', () {
      final contribution = lobbyModule(serverManager: _createManager());

      expect(contribution.redirect, isNull);
    });
  });
}
