import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_state.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/server_sidebar.dart';

import '../../../helpers/fakes.dart';

ServerManager _createManager() => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

Widget _buildSidebar({
  required Map<String, ServerEntry> servers,
  Map<String, UserProfile?> profiles = const {},
  VoidCallback? onServerTap,
  VoidCallback? onAddServer,
  VoidCallback? onNetworkInspector,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ServerSidebar(
        servers: servers,
        profiles: profiles,
        onServerTap: onServerTap ?? () {},
        onAddServer: onAddServer ?? () {},
        onNetworkInspector: onNetworkInspector ?? () {},
        onBusInspector: () {},
      ),
    ),
  );
}

void main() {
  group('ServerSidebar', () {
    testWidgets('displays connected servers with formatted URLs',
        (tester) async {
      final manager = _createManager();
      manager.addServer(
        serverId: 'http://srv1.test',
        serverUrl: Uri.parse('http://srv1.test'),
        requiresAuth: false,
      );
      manager.addServer(
        serverId: 'http://srv2.test:9000',
        serverUrl: Uri.parse('http://srv2.test:9000'),
        requiresAuth: false,
      );

      await tester.pumpWidget(_buildSidebar(servers: manager.servers.value));

      expect(find.text('http://srv1.test'), findsOneWidget);
      expect(find.text('http://srv2.test:9000'), findsOneWidget);
    });

    testWidgets('shows no-auth label for servers without authentication',
        (tester) async {
      final manager = _createManager();
      manager.addServer(
        serverId: 'http://localhost:8000',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );

      await tester.pumpWidget(_buildSidebar(servers: manager.servers.value));

      expect(find.text('No authentication required'), findsOneWidget);
    });

    testWidgets('shows Add Server button that fires callback', (tester) async {
      var addTapped = false;

      await tester.pumpWidget(_buildSidebar(
        servers: const {},
        onAddServer: () => addTapped = true,
      ));

      expect(find.text('Home'), findsOneWidget);
      await tester.tap(find.text('Home'));
      expect(addTapped, isTrue);
    });

    testWidgets('shows Network Inspector button that fires callback',
        (tester) async {
      var inspectorTapped = false;

      await tester.pumpWidget(_buildSidebar(
        servers: const {},
        onNetworkInspector: () => inspectorTapped = true,
      ));

      expect(find.text('Network Inspector'), findsOneWidget);
      await tester.tap(find.text('Network Inspector'));
      expect(inspectorTapped, isTrue);
    });
  });
}
