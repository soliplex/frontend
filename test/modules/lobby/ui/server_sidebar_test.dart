import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:soliplex_design/soliplex_design.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/core/app_identity.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_providers.dart';
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
  AppIdentity? identity,
  String? selectedServerId,
  void Function(String serverId)? onSelectServer,
  void Function(String serverId)? onSignIn,
  VoidCallback? onAddServer,
  VoidCallback? onNetworkInspector,
  VoidCallback? onVersions,
  List<Override> overrides = const [],
  ThemeData? theme,
}) {
  // The per-tile ⋮ menu is a ConsumerWidget, so the tree needs a ProviderScope;
  // the auth providers are only read when a logout fires.
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: theme,
      home: Scaffold(
        body: ServerSidebar(
          servers: servers,
          serverManager: serverManager ?? _createManager(),
          profiles: profiles,
          identity: identity ?? testIdentity(),
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

    testWidgets('app name renders in the brand font when configured',
        (tester) async {
      final theme = lowerBrandTheme(
        const BrandTheme.soliplex().copyWith(
          typography: const BrandTypography(brandFamily: 'Squada One'),
        ),
        Brightness.light,
      );
      await tester.pumpWidget(_buildSidebar(
        servers: const {},
        theme: theme,
      ));

      final nameText = tester.widget<Text>(find.text('Test App'));
      expect(nameText.style?.fontFamily, 'Squada One');
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

    testWidgets('a server with a name shows the name, not the raw address',
        (tester) async {
      final manager = _createManager();
      manager.addServer(
        serverId: 'https://api.example.com',
        serverUrl: Uri.parse('https://api.example.com'),
        requiresAuth: false,
        name: 'Demo Server',
      );

      await tester.pumpWidget(_buildSidebar(servers: manager.servers.value));

      expect(find.text('Demo Server'), findsOneWidget);
      expect(find.text('https://api.example.com'), findsNothing);
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
      testWidgets(
          'a disconnected server offers Sign in, Copy server address, '
          'and Remove', (tester) async {
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
        expect(find.text('Copy server address'), findsOneWidget);
        expect(find.text('Remove'), findsOneWidget);
        expect(find.text('Log out'), findsNothing);

        await tester.tap(find.text('Sign in'));
        await tester.pumpAndSettle();
        expect(signedIn, 'srv');
      });

      testWidgets(
          'a connected no-auth server offers Copy server address and Remove',
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
        expect(find.text('Copy server address'), findsOneWidget);
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
        expect(find.text('Copy server address'), findsOneWidget);
        expect(find.text('Remove'), findsOneWidget);
        expect(find.text('Sign in'), findsNothing);
      });

      testWidgets('Copy server address copies the full URL and confirms',
          (tester) async {
        final manager = _createManager();
        manager.addServer(
          serverId: 'srv',
          serverUrl: Uri.parse('https://api.example.com'),
          requiresAuth: false,
        );

        String? copied;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );

        await tester.pumpWidget(_buildSidebar(
          servers: manager.servers.value,
          serverManager: manager,
          // Selected so the hover-revealed ⋮ is shown (no mouse in the test).
          selectedServerId: 'srv',
        ));

        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
        expect(find.text('Copy server address'), findsOneWidget);

        await tester.tap(find.text('Copy server address'));
        await tester.pumpAndSettle();

        // The full scheme://host address is copied, and a SnackBar confirms it.
        expect(copied, 'https://api.example.com');
        expect(find.text('Copied https://api.example.com'), findsOneWidget);
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

    group('log-out failure', () {
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

      // A connected, authenticated server selected so its ⋮ is shown, wired to
      // a FakeAuthFlow whose endSession fails — the native log-out path then
      // preserves the session and surfaces the error.
      (ServerManager, ServerEntry, FakeAuthFlow) failingLogout() {
        final manager = _createManager();
        final entry = manager.addServer(
          serverId: 'srv',
          serverUrl: Uri.parse('https://api.example.com'),
        );
        signIn(entry);
        final flow = FakeAuthFlow()
          ..endSessionError = Exception('network down');
        return (manager, entry, flow);
      }

      List<Override> overridesFor(FakeAuthFlow flow) => [
            authFlowProvider.overrideWithValue(flow),
            probeClientProvider.overrideWithValue(FakeHttpClient()),
          ];

      Future<void> tapLogOut(WidgetTester tester) async {
        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Log out'));
        await tester.pumpAndSettle();
      }

      // Opens the menu that replaces the ⋮ after a failed log-out.
      Future<void> openErrorMenu(WidgetTester tester) async {
        await tester.tap(find.byIcon(Icons.error_outline));
        await tester.pumpAndSettle();
      }

      testWidgets('surfaces an error affordance and preserves the session',
          (tester) async {
        final (manager, entry, flow) = failingLogout();

        await tester.pumpWidget(_buildSidebar(
          servers: manager.servers.value,
          serverManager: manager,
          selectedServerId: 'srv',
          overrides: overridesFor(flow),
        ));
        await tapLogOut(tester);

        // The ⋮ is replaced by an error icon; the session is intact (the IdP
        // round-trip failed, so the local session was not cleared).
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        expect(entry.auth.isAuthenticated, isTrue);
      });

      testWidgets('the error menu offers retry, detail, and remove',
          (tester) async {
        final (manager, _, flow) = failingLogout();

        await tester.pumpWidget(_buildSidebar(
          servers: manager.servers.value,
          serverManager: manager,
          selectedServerId: 'srv',
          overrides: overridesFor(flow),
        ));
        await tapLogOut(tester);
        await openErrorMenu(tester);

        expect(find.text('Try again'), findsOneWidget);
        expect(find.text('Show error detail'), findsOneWidget);
        expect(find.text('Remove server'), findsOneWidget);
      });

      testWidgets('Show error detail opens a dialog with the message',
          (tester) async {
        final (manager, _, flow) = failingLogout();

        await tester.pumpWidget(_buildSidebar(
          servers: manager.servers.value,
          serverManager: manager,
          selectedServerId: 'srv',
          overrides: overridesFor(flow),
        ));
        await tapLogOut(tester);
        await openErrorMenu(tester);
        await tester.tap(find.text('Show error detail'));
        await tester.pumpAndSettle();

        expect(find.text('Log out failed'), findsOneWidget);
        expect(find.textContaining('network down'), findsWidgets);

        // Closing the dialog leaves the persistent error affordance in place.
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
      });

      testWidgets('Try again retries and clears the error once it succeeds',
          (tester) async {
        final (manager, entry, flow) = failingLogout();

        await tester.pumpWidget(_buildSidebar(
          servers: manager.servers.value,
          serverManager: manager,
          selectedServerId: 'srv',
          overrides: overridesFor(flow),
        ));
        await tapLogOut(tester);

        // The IdP recovers; the retry now signs out cleanly.
        flow.endSessionError = null;
        await openErrorMenu(tester);
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();

        expect(entry.auth.isAuthenticated, isFalse);
        expect(find.byIcon(Icons.error_outline), findsNothing);
      });

      testWidgets(
          'Remove server drops the entry even when sign-out keeps '
          'failing', (tester) async {
        final (manager, _, flow) = failingLogout();

        await tester.pumpWidget(_buildSidebar(
          servers: manager.servers.value,
          serverManager: manager,
          selectedServerId: 'srv',
          overrides: overridesFor(flow),
        ));
        await tapLogOut(tester);

        // endSessionError stays set, so the escape hatch's best-effort
        // sign-out fails again — the server must still be removed.
        await openErrorMenu(tester);
        await tester.tap(find.text('Remove server'));
        await tester.pumpAndSettle();

        expect(manager.servers.value.containsKey('srv'), isFalse);
      });

      testWidgets(
          'an in-flight log-out replaces the tile menu so it can not '
          'be re-triggered', (tester) async {
        final manager = _createManager();
        final entry = manager.addServer(
          serverId: 'srv',
          serverUrl: Uri.parse('https://api.example.com'),
        );
        signIn(entry);
        final completer = Completer<void>();
        final flow = FakeAuthFlow()..endSessionCompleter = completer;

        await tester.pumpWidget(_buildSidebar(
          servers: manager.servers.value,
          serverManager: manager,
          selectedServerId: 'srv',
          overrides: overridesFor(flow),
        ));
        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Log out'));
        await tester.pump(); // start the round-trip; the completer is pending

        // The tile's ⋮ is gone (only the account bar's remains), so a second
        // log-out/remove can't be fired while the first is outstanding.
        expect(find.byIcon(Icons.more_vert), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        completer.complete();
        await tester.pumpAndSettle();
        expect(entry.auth.isAuthenticated, isFalse);
      });
    });

    group('log out and remove', () {
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

      List<Override> overridesFor(RecordingAuthFlow flow) => [
            authFlowProvider.overrideWithValue(flow),
            probeClientProvider.overrideWithValue(FakeHttpClient()),
          ];

      testWidgets('logging out clears the session and restores the ⋮',
          (tester) async {
        final manager = _createManager();
        final entry = manager.addServer(
          serverId: 'srv',
          serverUrl: Uri.parse('https://api.example.com'),
        );
        signIn(entry);
        final flow = RecordingAuthFlow();

        await tester.pumpWidget(_buildSidebar(
          servers: manager.servers.value,
          serverManager: manager,
          selectedServerId: 'srv',
          overrides: overridesFor(flow),
        ));
        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Log out'));
        await tester.pumpAndSettle();

        expect(flow.endSessionCalled, isTrue);
        expect(entry.auth.isAuthenticated, isFalse);
        expect(find.byIcon(Icons.error_outline), findsNothing);
      });

      testWidgets('removing a connected authenticated server logs out first',
          (tester) async {
        final manager = _createManager();
        final entry = manager.addServer(
          serverId: 'srv',
          serverUrl: Uri.parse('https://api.example.com'),
        );
        signIn(entry);
        final flow = RecordingAuthFlow();

        await tester.pumpWidget(_buildSidebar(
          servers: manager.servers.value,
          serverManager: manager,
          selectedServerId: 'srv',
          overrides: overridesFor(flow),
        ));
        await tester.tap(find.byIcon(Icons.more_vert).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove'));
        await tester.pumpAndSettle();

        // The IdP session is ended before the entry is dropped, so it can't
        // outlive the removed server.
        expect(flow.endSessionCalled, isTrue);
        expect(manager.servers.value.containsKey('srv'), isFalse);
      });
    });

    group('status dot', () {
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

      Color dotColor(WidgetTester tester, String tooltip) {
        final container = tester.widget<Container>(
          find.descendant(
            of: find.byTooltip(tooltip),
            matching: find.byType(Container),
          ),
        );
        return (container.decoration! as BoxDecoration).color!;
      }

      testWidgets(
          'shows a distinct dot per sign-in state, and none for a no-auth '
          'server', (tester) async {
        final manager = _createManager();
        manager.addServer(
          serverId: 'noauth',
          serverUrl: Uri.parse('http://localhost:8000'),
          requiresAuth: false,
        );
        manager.addServer(
          serverId: 'signedout',
          serverUrl: Uri.parse('https://out.example.com'),
        );
        final signedIn = manager.addServer(
          serverId: 'signedin',
          serverUrl: Uri.parse('https://in.example.com'),
        );
        signIn(signedIn);

        await tester.pumpWidget(_buildSidebar(servers: manager.servers.value));

        // A no-auth server is always ready, so it carries no status dot.
        expect(find.byTooltip('No authentication required'), findsNothing);

        // The two sign-in states each get a labelled dot...
        expect(find.byTooltip('Not signed in'), findsOneWidget);
        expect(find.byTooltip('Signed in'), findsOneWidget);

        // ...in different colors.
        expect(
          dotColor(tester, 'Not signed in'),
          isNot(dotColor(tester, 'Signed in')),
        );
      });

      testWidgets('flips from signed-in to signed-out on session expiry',
          (tester) async {
        final manager = _createManager();
        final entry = manager.addServer(
          serverId: 'srv',
          serverUrl: Uri.parse('https://api.example.com'),
        );
        signIn(entry);

        // Snapshot the map once; the dot must update from the per-entry
        // session signal, not a map mutation.
        await tester.pumpWidget(_buildSidebar(servers: manager.servers.value));
        expect(find.byTooltip('Signed in'), findsOneWidget);
        expect(find.byTooltip('Not signed in'), findsNothing);

        entry.auth.markSessionExpired();
        await tester.pump();

        expect(find.byTooltip('Not signed in'), findsOneWidget);
        expect(find.byTooltip('Signed in'), findsNothing);
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
