import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/lobby_screen.dart';

import '../../../helpers/fakes.dart';

ServerManager _createManager() => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

Widget _buildApp(
  ServerManager manager, {
  void Function(Uri location)? onHomeRoute,
}) {
  final router = GoRouter(
    initialLocation: '/lobby',
    routes: [
      GoRoute(
        path: '/lobby',
        builder: (_, __) => LobbyScreen(serverManager: manager),
      ),
      GoRoute(
        path: '/servers',
        builder: (_, __) => const Scaffold(body: Text('Servers')),
      ),
      GoRoute(
        path: '/',
        builder: (_, state) {
          onHomeRoute?.call(state.uri);
          return const Scaffold(body: Text('Home'));
        },
      ),
    ],
  );
  return ProviderScope(child: MaterialApp.router(routerConfig: router));
}

void main() {
  group('LobbyScreen', () {
    testWidgets('shows sidebar on wide viewport with Add Server visible',
        (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final manager = _createManager();
      await tester.pumpWidget(_buildApp(manager));
      await tester.pump();

      // No hamburger menu icon in wide layout
      expect(find.byIcon(Icons.menu), findsNothing);

      // Sidebar Add Server button is directly visible (no Drawer wrapping it)
      expect(find.byType(Drawer), findsNothing);
      expect(find.text('Add Server'), findsWidgets);
    });

    testWidgets(
        'uses drawer on narrow viewport — hamburger opens drawer with Add Server',
        (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final manager = _createManager();
      await tester.pumpWidget(_buildApp(manager));
      await tester.pump();

      // Hamburger icon present in narrow layout
      expect(find.byIcon(Icons.menu), findsOneWidget);

      // Drawer not yet open
      expect(find.byType(Drawer), findsNothing);

      // Open the drawer
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Drawer is now open and contains the sidebar with Add Server
      expect(find.byType(Drawer), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Drawer),
          matching: find.text('Add Server'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows empty state CTA when no servers connected',
        (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final manager = _createManager();
      await tester.pumpWidget(_buildApp(manager));
      await tester.pump();

      // Empty state: prominent Add Server CTA in the room content area
      expect(find.text('No servers connected'), findsOneWidget);
    });

    testWidgets(
      'expired-session row renders Sign in button that routes to '
      'homeWithUrl with returnTo=lobby',
      (tester) async {
        // The whole purpose of keeping the expired row visible is to
        // give the user a way to recover. A regression that removed
        // the button or mis-wired its onPressed would re-introduce
        // the "invisible expired server" bug this commit fixes.
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

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
        entry.auth.markSessionExpired();

        Uri? homeLocation;
        await tester.pumpWidget(
          _buildApp(manager, onHomeRoute: (uri) => homeLocation = uri),
        );
        await tester.pump();

        // The panel description is unique to the RoomsExpired arm
        // (the sidebar tile also renders "Session expired", but only
        // as a subtitle), so it pins the panel without ambiguity.
        expect(
          find.text('Sign in again to view rooms on this server.'),
          findsOneWidget,
        );
        expect(find.text('Sign in'), findsOneWidget);

        await tester.tap(find.text('Sign in'));
        await tester.pumpAndSettle();

        expect(homeLocation, isNotNull);
        expect(
          homeLocation!.queryParameters['url'],
          'https://api.example.com',
        );
        expect(homeLocation!.queryParameters['returnTo'], '/lobby');
      },
    );
  });
}
