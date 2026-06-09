import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
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
  String? selectedServerId,
  void Function(String serverId)? onSelectServer,
  VoidCallback? onServerTap,
  VoidCallback? onAddServer,
  VoidCallback? onNetworkInspector,
  VoidCallback? onVersions,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ServerSidebar(
        servers: servers,
        profiles: profiles,
        selectedServerId: selectedServerId,
        onSelectServer: onSelectServer ?? (_) {},
        onServerTap: onServerTap ?? () {},
        onAddServer: onAddServer ?? () {},
        onNetworkInspector: onNetworkInspector ?? () {},
        onVersions: onVersions ?? () {},
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

    testWidgets('Home action button fires the add-server callback',
        (tester) async {
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

    testWidgets(
      'subtitle reacts to session flipping to ExpiredSession '
      'without any server-map mutation',
      (tester) async {
        // The ServerSidebar receives a `servers` map snapshot from its
        // parent. The parent only rebuilds when the map mutates (server
        // added/removed). A pure session-state flip on an existing entry
        // does not change the map. The subtitle reactivity therefore
        // must come from the tile itself watching the per-entry session
        // signal — without that, the subtitle would stale-display the
        // pre-flip label until something else triggered a rebuild.
        final manager = _createManager();
        final entry = manager.addServer(
          serverId: 'auth-server',
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

        // Snapshot the map once; we intentionally never refresh it.
        final servers = manager.servers.value;

        await tester.pumpWidget(_buildSidebar(servers: servers));
        expect(find.text('Signed in'), findsOneWidget);
        expect(find.text('Session expired'), findsNothing);

        entry.auth.markSessionExpired();
        await tester.pump();

        expect(find.text('Session expired'), findsOneWidget);
        expect(find.text('Signed in'), findsNothing);
      },
    );

    testWidgets('tapping a server tile fires onSelectServer with its id',
        (tester) async {
      final manager = _createManager();
      manager.addServer(
        serverId: 'http://srv1.test',
        serverUrl: Uri.parse('http://srv1.test'),
        requiresAuth: false,
      );

      String? selected;
      await tester.pumpWidget(_buildSidebar(
        servers: manager.servers.value,
        onSelectServer: (id) => selected = id,
      ));

      await tester.tap(find.text('http://srv1.test'));
      expect(selected, 'http://srv1.test');
    });

    testWidgets('the selected server tile is marked selected', (tester) async {
      final manager = _createManager();
      manager.addServer(
        serverId: 'http://srv1.test',
        serverUrl: Uri.parse('http://srv1.test'),
        requiresAuth: false,
      );
      manager.addServer(
        serverId: 'http://srv2.test',
        serverUrl: Uri.parse('http://srv2.test'),
        requiresAuth: false,
      );

      await tester.pumpWidget(_buildSidebar(
        servers: manager.servers.value,
        selectedServerId: 'http://srv2.test',
      ));

      ListTile tileFor(String url) =>
          tester.widget<ListTile>(find.widgetWithText(ListTile, url));
      expect(tileFor('http://srv2.test').selected, isTrue);
      expect(tileFor('http://srv1.test').selected, isFalse);
    });

    testWidgets('manage-servers button fires onServerTap', (tester) async {
      final manager = _createManager();
      manager.addServer(
        serverId: 'http://srv1.test',
        serverUrl: Uri.parse('http://srv1.test'),
        requiresAuth: false,
      );

      var managed = false;
      await tester.pumpWidget(_buildSidebar(
        servers: manager.servers.value,
        onServerTap: () => managed = true,
      ));

      await tester.tap(find.byIcon(Icons.settings_outlined));
      expect(managed, isTrue);
    });
  });
}
