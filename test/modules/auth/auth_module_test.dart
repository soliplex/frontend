import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_frontend/src/core/app_module.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_module.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';

import '../../helpers/fakes.dart';

class _NullContext implements AppModuleContext {
  @override
  T? module<T extends AppModule>() => null;
}

final _ctx = _NullContext();

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
      final contribution = _createModule().build(_ctx);
      final paths =
          contribution.routes.whereType<GoRoute>().map((r) => r.path).toList();
      expect(paths, containsAll(['/', '/servers', '/auth/callback']));
    });

    test('contributes a redirect', () {
      final contribution = _createModule().build(_ctx);
      expect(contribution.redirect, isNotNull);
    });

    test('contributes overrides for required providers', () {
      final contribution = _createModule().build(_ctx);
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
      final contribution = module.build(_ctx);
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
      final contribution = module.build(_ctx);
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
}
