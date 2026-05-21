import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_frontend/src/core/routes.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_module.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';

import '../../helpers/fakes.dart';

ServerManager _createServerManager() => ServerManager(
      authFactory: () => AuthSession(
        refreshService: FakeTokenRefreshService(),
      ),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

AuthAppModule _createModule({ServerManager? serverManager}) => AuthAppModule(
      serverManager: serverManager ?? _createServerManager(),
      probeClient: FakeHttpClient(),
      authFlow: FakeAuthFlow(),
      appName: 'Soliplex',
    );

void main() {
  group('AuthAppModule', () {
    test('contributes routes for /, /servers, /auth/callback', () {
      final contribution = _createModule().build();
      final paths =
          contribution.routes.whereType<GoRoute>().map((r) => r.path).toList();
      expect(paths, containsAll(['/', '/servers', '/auth/callback']));
    });

    test('contributes a redirect', () {
      final contribution = _createModule().build();
      expect(contribution.redirect, isNotNull);
    });

    test('contributes overrides for required providers', () {
      final contribution = _createModule().build();
      // At minimum: serverManager, authFlow, probeClient.
      // Optional overrides only added when non-null.
      expect(contribution.overrides, isNotEmpty);
    });
  });

  group('auth redirect', () {
    late ServerManager serverManager;
    late AuthAppModule module;
    late GoRouter router;

    Widget buildApp() {
      final contribution = module.build();
      router = GoRouter(
        initialLocation: '/',
        routes: [
          ...contribution.routes,
          GoRoute(
            path: '/chat',
            builder: (_, __) => const Text('Chat'),
          ),
        ],
        redirect: contribution.redirect,
      );
      return ProviderScope(
        overrides: contribution.overrides,
        child: MaterialApp.router(routerConfig: router),
      );
    }

    setUp(() {
      serverManager = _createServerManager();
      module = _createModule(serverManager: serverManager);
    });

    tearDown(() async => module.onDispose());

    testWidgets('stays on / when unauthenticated', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Soliplex'), findsOneWidget);
    });

    testWidgets('redirects /chat to / when unauthenticated', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      router.go('/chat');
      await tester.pumpAndSettle();

      expect(find.text('Soliplex'), findsOneWidget);
      expect(find.text('Chat'), findsNothing);
    });

    testWidgets('allows /auth/callback when unauthenticated', (tester) async {
      final contribution = module.build();
      router = GoRouter(
        initialLocation: '/auth/callback',
        routes: contribution.routes,
        redirect: contribution.redirect,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: contribution.overrides,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // Should show callback screen (with error since no params), not redirect to /
      expect(find.text('No callback parameters received.'), findsOneWidget);
    });

    testWidgets('allows /chat when authenticated', (tester) async {
      final entry = serverManager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );
      entry.auth.login(
        provider: const OidcProvider(
          discoveryUrl:
              'https://sso.example.com/.well-known/openid-configuration',
          clientId: 'soliplex',
        ),
        tokens: AuthTokens(
          accessToken: 'access',
          refreshToken: 'refresh',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      router.go('/chat');
      await tester.pumpAndSettle();

      expect(find.text('Chat'), findsOneWidget);
    });
  });

  group('per-server route guard', () {
    late ServerManager serverManager;
    late AuthAppModule module;
    late GoRouter router;

    const provider = OidcProvider(
      discoveryUrl: 'https://sso.example.com/.well-known/openid-configuration',
      clientId: 'soliplex',
    );

    AuthTokens tokens() => AuthTokens(
          accessToken: 'access',
          refreshToken: 'refresh',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        );

    Widget buildAppWithRoomRoute() {
      final contribution = module.build();
      router = GoRouter(
        initialLocation: '/',
        refreshListenable: module.refreshListenable,
        routes: [
          ...contribution.routes,
          GoRoute(
            path: '/room/:serverAlias/:roomId',
            builder: (_, state) => Text(
              'Room ${state.pathParameters['serverAlias']}/${state.pathParameters['roomId']}',
            ),
          ),
        ],
        redirect: contribution.redirect,
      );
      return ProviderScope(
        overrides: contribution.overrides,
        child: MaterialApp.router(routerConfig: router),
      );
    }

    setUp(() {
      serverManager = _createServerManager();
      module = _createModule(serverManager: serverManager);
    });

    tearDown(() async => module.onDispose());

    String currentLocation() =>
        router.routerDelegate.currentConfiguration.uri.toString();

    testWidgets(
      'redirects /room/A/x to homeWithUrl when server A is not connected',
      (tester) async {
        // Two servers: A signed out, B authenticated. Aggregate authState
        // stays Authenticated (B keeps us logged in), so the global guard
        // does nothing. The per-server guard must kick in.
        final a = serverManager.addServer(
          serverId: 'a',
          serverUrl: Uri.parse('https://a.example.com'),
        );
        final b = serverManager.addServer(
          serverId: 'b',
          serverUrl: Uri.parse('https://b.example.com'),
        );
        b.auth.login(provider: provider, tokens: tokens());

        await tester.pumpWidget(buildAppWithRoomRoute());
        await tester.pumpAndSettle();

        router.go('/room/${b.alias}/r1');
        await tester.pumpAndSettle();
        expect(currentLocation(), '/room/${b.alias}/r1');

        router.go('/room/${a.alias}/r1');
        // Don't pumpAndSettle — auto-connect on HomeScreen would hit
        // the fake HTTP client. We only care about the redirect target.
        await tester.pump();

        expect(
          currentLocation(),
          AppRoutes.homeWithUrl(
            a.serverUrl.toString(),
            returnTo: '/room/${a.alias}/r1',
          ),
        );
      },
    );

    testWidgets(
      'redirect re-evaluates when an active server flips to expired '
      'mid-session',
      (tester) async {
        final a = serverManager.addServer(
          serverId: 'a',
          serverUrl: Uri.parse('https://a.example.com'),
        );
        final b = serverManager.addServer(
          serverId: 'b',
          serverUrl: Uri.parse('https://b.example.com'),
        );
        a.auth.login(provider: provider, tokens: tokens());
        b.auth.login(provider: provider, tokens: tokens());

        await tester.pumpWidget(buildAppWithRoomRoute());
        await tester.pumpAndSettle();

        router.go('/room/${a.alias}/r1');
        await tester.pumpAndSettle();
        expect(currentLocation(), '/room/${a.alias}/r1');

        a.auth.markSessionExpired();
        // refreshListenable should fire on the per-server transition even
        // though B keeps the aggregate authenticated.
        await tester.pump();

        expect(
          currentLocation(),
          AppRoutes.homeWithUrl(
            a.serverUrl.toString(),
            returnTo: '/room/${a.alias}/r1',
          ),
        );
      },
    );
  });
}
