import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_module.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_read_markers.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/lobby_screen.dart';
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
        registry: RunRegistry(servers: emptyServers()),
        roomReadMarkers: RoomReadMarkers(),
        serverReadMarkers: ServerReadMarkers(),
      ).build();
      final paths =
          contribution.routes.whereType<GoRoute>().map((r) => r.path).toList();
      expect(paths, contains('/lobby'));
    });

    testWidgets('passes ?server= through to the lobby screen', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final contribution = LobbyAppModule(
        serverManager: _createManager(),
        identity: testIdentity(),
        registry: RunRegistry(servers: emptyServers()),
        roomReadMarkers: RoomReadMarkers(),
        serverReadMarkers: ServerReadMarkers(),
      ).build();

      await tester.pumpWidget(ProviderScope(
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/lobby?server=srv-7',
            routes: contribution.routes,
          ),
        ),
      ));

      // Routed through the module's own pageBuilder, so this fails if the route
      // stops reading the query parameter. The screen-level test cannot catch
      // that — its harness reads the parameter itself instead of using this
      // route.
      expect(
        tester.widget<LobbyScreen>(find.byType(LobbyScreen)).initialServerId,
        'srv-7',
      );
    });

    test('does not contribute a redirect', () {
      final contribution = LobbyAppModule(
        serverManager: _createManager(),
        identity: testIdentity(),
        registry: RunRegistry(servers: emptyServers()),
        roomReadMarkers: RoomReadMarkers(),
        serverReadMarkers: ServerReadMarkers(),
      ).build();
      expect(contribution.redirect, isNull);
    });
  });
}
