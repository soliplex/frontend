@TestOn('browser')
library;

// Run with: `flutter test --platform chrome <this file>`.
//
// Default `flutter test` (VM platform) silently skips this file — the
// project's CI pipeline does not currently run browser tests, so a
// regression to the web-specific ordering this test pins would not be
// caught automatically. Until CI gains a `--platform chrome` step,
// developers touching `_logout` in
// `lib/src/modules/auth/ui/server_list_screen.dart` should run this
// file manually.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;
import 'package:soliplex_frontend/src/modules/auth/auth_providers.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/auth/ui/server_list_screen.dart';

import '../../../helpers/fakes.dart';

ServerManager _createServerManager() => ServerManager(
      authFactory: () => AuthSession(
        refreshService: FakeTokenRefreshService(),
      ),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

void _loginEntry(ServerEntry entry) {
  entry.auth.login(
    provider: const OidcProvider(
      discoveryUrl: 'https://sso.example.com/.well-known/openid-configuration',
      clientId: 'soliplex',
    ),
    tokens: AuthTokens(
      accessToken: 'access',
      refreshToken: 'refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    ),
  );
}

Widget _buildApp({
  required ServerManager serverManager,
  required RecordingAuthFlow authFlow,
  required SoliplexHttpClient probeClient,
}) {
  final router = GoRouter(
    initialLocation: '/servers',
    routes: [
      GoRoute(
        path: '/servers',
        builder: (_, __) => ServerListScreen(serverManager: serverManager),
      ),
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: Text('Home')),
      ),
      GoRoute(
        path: '/lobby',
        builder: (_, __) => const Scaffold(body: Text('Lobby')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      serverManagerProvider.overrideWithValue(serverManager),
      authFlowProvider.overrideWithValue(authFlow),
      probeClientProvider.overrideWithValue(probeClient),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  group('ServerListScreen logout on web', () {
    // Pins the web-specific ordering documented on `_logout`:
    // `entry.auth.logout()` runs BEFORE `authFlow.endSession` on web
    // (the inverse of native). Reason: `WebAuthFlow.endSession` is a
    // full-page navigation; clearing local state after the navigation
    // would race the page unload and risk persisting a stale
    // `ActiveSession`.
    testWidgets('logout clears local before calling endSession',
        (tester) async {
      final serverManager = _createServerManager();
      final entry = serverManager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );
      _loginEntry(entry);

      final discoveryJson = jsonEncode({
        'token_endpoint': 'https://sso.example.com/token',
        'end_session_endpoint': 'https://sso.example.com/logout',
      });
      final probeClient = FakeHttpClient()
        ..onRequest = (method, uri) async {
          return HttpResponse(
            statusCode: 200,
            bodyBytes: Uint8List.fromList(utf8.encode(discoveryJson)),
          );
        };

      bool wasAuthenticatedDuringEndSession = true;
      final authFlow = RecordingAuthFlow(
        onEndSession: () {
          wasAuthenticatedDuringEndSession = entry.auth.isAuthenticated;
        },
      );

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        authFlow: authFlow,
        probeClient: probeClient,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();

      expect(authFlow.endSessionCalled, isTrue);
      // The inverse of the native ordering test: on web, local has
      // been cleared by the time endSession runs.
      expect(wasAuthenticatedDuringEndSession, isFalse);
      expect(entry.auth.isAuthenticated, isFalse);
    });
  });
}
