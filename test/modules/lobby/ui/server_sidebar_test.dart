import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/core/branding.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/lobby/lobby_state.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/server_sidebar.dart';
import 'package:soliplex_frontend/version.dart';

import '../../../helpers/fakes.dart';

ServerManager _createManager() => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

Widget _buildSidebar({
  required Map<String, ServerEntry> servers,
  ServerManager? serverManager,
  Map<String, UserProfile?> profiles = const {},
  SoliplexBranding? branding,
  String? selectedServerId,
  void Function(String serverId)? onSelectServer,
  void Function(String serverId)? onSignIn,
  VoidCallback? onAddServer,
  VoidCallback? onNetworkInspector,
  VoidCallback? onVersions,
}) {
  // The per-tile ⋮ menu is a ConsumerWidget, so the tree needs a ProviderScope;
  // the auth providers are only read when a logout fires.
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: ServerSidebar(
          servers: servers,
          serverManager: serverManager ?? _createManager(),
          profiles: profiles,
          branding: branding ?? testBranding(),
          selectedServerId: selectedServerId,
          onSelectServer: onSelectServer ?? (_) {},
          onSignIn: onSignIn ?? (_) {},
          onAddServer: onAddServer ?? () {},
          onNetworkInspector: onNetworkInspector ?? () {},
          onVersions: onVersions ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  group('ServerSidebar', () {
    testWidgets('header shows the brand logo, app name, and version',
        (tester) async {
      await tester.pumpWidget(_buildSidebar(servers: const {}));

      expect(find.byType(BrandLogo), findsOneWidget);
      expect(find.text('Test App'), findsOneWidget);
      expect(find.text('v$soliplexVersion'), findsOneWidget);
    });

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

    testWidgets('the more menu routes Network Inspector / Versions',
        (tester) async {
      var inspector = 0;
      var versions = 0;

      await tester.pumpWidget(_buildSidebar(
        servers: const {},
        onNetworkInspector: () => inspector++,
        onVersions: () => versions++,
      ));

      // Open the menu: no "Home" item (the Add Server button already routes
      // home), and selecting Network Inspector routes and closes it.
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsNothing);
      await tester.tap(find.text('Network Inspector'));
      await tester.pumpAndSettle();
      expect(inspector, 1);

      // Reopen for Versions.
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Versions'));
      await tester.pumpAndSettle();
      expect(versions, 1);
    });

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

    testWidgets('server management lives in the tile menu, not a gear',
        (tester) async {
      final manager = _createManager();
      manager.addServer(
        serverId: 'http://srv1.test',
        serverUrl: Uri.parse('http://srv1.test'),
        requiresAuth: false,
      );

      await tester.pumpWidget(_buildSidebar(servers: manager.servers.value));

      // No standalone "Manage servers" gear; each tile carries its own ⋮.
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      // One ⋮ on the tile plus the account bar's ⋮.
      expect(find.byIcon(Icons.more_vert), findsNWidgets(2));
    });

    group('tile ⋮ menu', () {
      testWidgets('a disconnected server offers Sign in and Remove',
          (tester) async {
        final manager = _createManager();
        // requiresAuth + NoSession => not connected.
        manager.addServer(
          serverId: 'srv',
          serverUrl: Uri.parse('https://api.example.com'),
        );

        String? signedIn;
        await tester.pumpWidget(_buildSidebar(
          servers: manager.servers.value,
          serverManager: manager,
          // Selected so the hover-revealed ⋮ is shown (no mouse in the test).
          selectedServerId: 'srv',
          onSignIn: (id) => signedIn = id,
        ));

        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
        expect(find.text('Sign in'), findsOneWidget);
        expect(find.text('Remove'), findsOneWidget);
        expect(find.text('Log out'), findsNothing);

        await tester.tap(find.text('Sign in'));
        await tester.pumpAndSettle();
        expect(signedIn, 'srv');
      });

      testWidgets('a connected no-auth server offers only Remove',
          (tester) async {
        final manager = _createManager();
        manager.addServer(
          serverId: 'srv',
          serverUrl: Uri.parse('http://localhost:8000'),
          requiresAuth: false,
        );

        await tester.pumpWidget(_buildSidebar(
          servers: manager.servers.value,
          serverManager: manager,
          // Selected so the hover-revealed ⋮ is shown (no mouse in the test).
          selectedServerId: 'srv',
        ));

        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
        expect(find.text('Remove'), findsOneWidget);
        expect(find.text('Sign in'), findsNothing);
        expect(find.text('Log out'), findsNothing);

        await tester.tap(find.text('Remove'));
        await tester.pumpAndSettle();
        expect(manager.servers.value.containsKey('srv'), isFalse);
      });

      testWidgets('a connected authenticated server offers Log out and Remove',
          (tester) async {
        final manager = _createManager();
        final entry = manager.addServer(
          serverId: 'srv',
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

        await tester.pumpWidget(_buildSidebar(
          servers: manager.servers.value,
          serverManager: manager,
          selectedServerId: 'srv',
        ));

        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
        expect(find.text('Log out'), findsOneWidget);
        expect(find.text('Remove'), findsOneWidget);
        expect(find.text('Sign in'), findsNothing);
      });

      testWidgets('the tile ⋮ is hidden until the tile is hovered',
          (tester) async {
        final manager = _createManager();
        manager.addServer(
          serverId: 'srv',
          serverUrl: Uri.parse('http://localhost:8000'),
          requiresAuth: false,
        );

        // Not hovered and not selected: the ⋮ is present but not interactive,
        // so a tap where it sits falls through and opens no menu.
        await tester.pumpWidget(_buildSidebar(
          servers: manager.servers.value,
          serverManager: manager,
        ));
        await tester.tap(find.byIcon(Icons.more_vert).first,
            warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(find.text('Remove'), findsNothing);

        // Hover the tile: the ⋮ reveals and now opens.
        final gesture =
            await tester.createGesture(kind: PointerDeviceKind.mouse);
        await gesture.addPointer(location: Offset.zero);
        addTearDown(gesture.removePointer);
        await gesture
            .moveTo(tester.getCenter(find.text('http://localhost:8000')));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
        expect(find.text('Remove'), findsOneWidget);
      });
    });

    group('account block', () {
      ServerEntry addServer(ServerManager m, {required bool requiresAuth}) =>
          m.addServer(
            serverId: 'srv',
            serverUrl: Uri.parse('https://api.example.com'),
            requiresAuth: requiresAuth,
          );

      void signIn(ServerEntry entry) => entry.auth.login(
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

      testWidgets('shows Guest for a no-auth server', (tester) async {
        final manager = _createManager();
        addServer(manager, requiresAuth: false);

        await tester.pumpWidget(_buildSidebar(
          servers: manager.servers.value,
          selectedServerId: 'srv',
        ));

        expect(find.text('Guest'), findsOneWidget);
        expect(find.text('G'), findsOneWidget);
      });

      testWidgets('shows Guest when auth is required but not signed in',
          (tester) async {
        final manager = _createManager();
        addServer(manager, requiresAuth: true); // session is NoSession

        await tester.pumpWidget(_buildSidebar(
          servers: manager.servers.value,
          selectedServerId: 'srv',
        ));

        expect(find.text('Guest'), findsOneWidget);
      });

      testWidgets('shows the signed-in name, email, and initial',
          (tester) async {
        final manager = _createManager();
        final entry = addServer(manager, requiresAuth: true);
        signIn(entry);

        await tester.pumpWidget(_buildSidebar(
          servers: manager.servers.value,
          selectedServerId: 'srv',
          profiles: const {
            'srv': UserProfile(
              givenName: 'Ada',
              familyName: 'Lovelace',
              email: 'ada@example.com',
              preferredUsername: 'ada',
            ),
          },
        ));

        // Identity lives only in the account block now (the tile has no
        // subtitle); name, email, and avatar initial each render once.
        expect(find.text('Ada Lovelace'), findsOneWidget);
        expect(find.text('ada@example.com'), findsOneWidget);
        expect(find.text('A'), findsOneWidget); // avatar initial
      });

      testWidgets('falls back to preferred_username when no full name',
          (tester) async {
        final manager = _createManager();
        final entry = addServer(manager, requiresAuth: true);
        signIn(entry);

        await tester.pumpWidget(_buildSidebar(
          servers: manager.servers.value,
          selectedServerId: 'srv',
          profiles: const {
            'srv': UserProfile(
              givenName: '',
              familyName: '',
              email: '',
              preferredUsername: 'ada99',
            ),
          },
        ));

        // Block-only identity; the preferred_username and initial each
        // render once.
        expect(find.text('ada99'), findsOneWidget);
        expect(find.text('A'), findsOneWidget);
      });

      testWidgets(
          'shows Signed in when authenticated but the profile is absent',
          (tester) async {
        final manager = _createManager();
        final entry = addServer(manager, requiresAuth: true);
        signIn(entry);

        // No profiles entry for 'srv': the profile fetch has not resolved
        // (or failed), but the session is active.
        await tester.pumpWidget(_buildSidebar(
          servers: manager.servers.value,
          selectedServerId: 'srv',
        ));

        // The block falls back to the generic label; initial is block-only.
        expect(find.text('Signed in'), findsOneWidget);
        expect(find.text('S'), findsOneWidget);
      });

      testWidgets('omits the email line when the profile has no email',
          (tester) async {
        final manager = _createManager();
        final entry = addServer(manager, requiresAuth: true);
        signIn(entry);

        await tester.pumpWidget(_buildSidebar(
          servers: manager.servers.value,
          selectedServerId: 'srv',
          profiles: const {
            'srv': UserProfile(
              givenName: 'Ada',
              familyName: 'Lovelace',
              email: '',
              preferredUsername: 'ada',
            ),
          },
        ));

        expect(find.text('Ada Lovelace'), findsOneWidget);
        expect(find.textContaining('@'), findsNothing);
      });

      testWidgets(
          'reacts to the selected server signing out without a server-map '
          'mutation', (tester) async {
        final manager = _createManager();
        final entry = addServer(manager, requiresAuth: true);
        signIn(entry);

        // Snapshot the map once and never refresh it: the block must update
        // from the per-entry session signal, not from a map change.
        final servers = manager.servers.value;
        await tester.pumpWidget(_buildSidebar(
          servers: servers,
          selectedServerId: 'srv',
          profiles: const {
            'srv': UserProfile(
              givenName: 'Ada',
              familyName: 'Lovelace',
              email: 'ada@example.com',
              preferredUsername: 'ada',
            ),
          },
        ));
        expect(find.text('Ada Lovelace'), findsOneWidget);

        entry.auth.markSessionExpired();
        await tester.pump();

        // The block falls back to Guest; the signed-in name is gone.
        expect(find.text('Guest'), findsOneWidget);
        expect(find.text('Ada Lovelace'), findsNothing);
      });
    });
  });
}
