import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;
import 'package:soliplex_frontend/src/modules/auth/auth_providers.dart';
import 'package:soliplex_frontend/src/modules/auth/platform/auth_flow.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/auth/ui/server_list_screen.dart';

import '../../../helpers/fakes.dart';

/// A bare [Error] (not an [Exception]) used to exercise the else-branch of
/// [_friendlyLogoutError] without leaking a runtime type name.
class _LogoutBoom extends Error {}

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

String? _lastLocation;

Widget _buildApp({
  required ServerManager serverManager,
  AuthFlow? authFlow,
  SoliplexHttpClient? probeClient,
}) {
  final router = GoRouter(
    initialLocation: '/servers',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, state) {
          _lastLocation = state.uri.toString();
          return Scaffold(body: Text('Home: ${state.uri}'));
        },
      ),
      GoRoute(
        path: '/servers',
        builder: (_, __) => ServerListScreen(serverManager: serverManager),
      ),
      GoRoute(
        path: '/lobby',
        builder: (_, __) => const Scaffold(body: Text('Lobby placeholder')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      serverManagerProvider.overrideWithValue(serverManager),
      authFlowProvider.overrideWithValue(authFlow ?? FakeAuthFlow()),
      if (probeClient != null)
        probeClientProvider.overrideWithValue(probeClient),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  setUp(() => _lastLocation = null);

  group('ServerListScreen', () {
    testWidgets('shows all servers with host names', (tester) async {
      final serverManager = _createServerManager();
      serverManager.addServer(
        serverId: 'one',
        serverUrl: Uri.parse('https://one.example.com'),
      );
      final entry2 = serverManager.addServer(
        serverId: 'two',
        serverUrl: Uri.parse('https://two.example.com'),
      );
      _loginEntry(entry2);

      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      expect(find.text('https://one.example.com'), findsOneWidget);
      expect(find.text('https://two.example.com'), findsOneWidget);
    });

    testWidgets('shows Connected and Disconnected section headers',
        (tester) async {
      final serverManager = _createServerManager();
      serverManager.addServer(
        serverId: 'disconnected',
        serverUrl: Uri.parse('https://disconnected.example.com'),
      );
      final connected = serverManager.addServer(
        serverId: 'connected',
        serverUrl: Uri.parse('https://connected.example.com'),
      );
      _loginEntry(connected);

      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      expect(find.text('Connected (1)'), findsOneWidget);
      expect(find.text('Disconnected (1)'), findsOneWidget);
    });

    testWidgets('hides Disconnected section when all servers connected',
        (tester) async {
      final serverManager = _createServerManager();
      final entry = serverManager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );
      _loginEntry(entry);

      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      expect(find.text('Connected (1)'), findsOneWidget);
      expect(find.textContaining('Disconnected'), findsNothing);
    });

    testWidgets('hides Connected section when all servers disconnected',
        (tester) async {
      final serverManager = _createServerManager();
      serverManager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );

      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      expect(find.text('Disconnected (1)'), findsOneWidget);
      expect(find.textContaining('Connected ('), findsNothing);
    });

    testWidgets('Log out button logs out a connected server', (tester) async {
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

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        probeClient: probeClient,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Connected (1)'), findsOneWidget);

      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();

      expect(entry.auth.isAuthenticated, isFalse);
      expect(find.text('Disconnected (1)'), findsOneWidget);
    });

    testWidgets('delete button removes server', (tester) async {
      final serverManager = _createServerManager();
      serverManager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );

      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      expect(find.text('https://api.example.com'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('https://api.example.com'), findsNothing);
    });

    testWidgets('no-auth server appears in Connected section', (tester) async {
      final serverManager = _createServerManager();
      serverManager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );

      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      expect(find.text('Connected (1)'), findsOneWidget);
    });

    testWidgets('no-auth server has no Log out button', (tester) async {
      final serverManager = _createServerManager();
      serverManager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );

      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      expect(find.text('Log out'), findsNothing);
    });

    testWidgets('logout calls endSession before clearing local auth',
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

      bool wasAuthenticatedDuringEndSession = false;
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
      expect(wasAuthenticatedDuringEndSession, isTrue);
      expect(entry.auth.isAuthenticated, isFalse);
    });

    testWidgets('updates when servers change externally', (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      expect(find.text('https://api.example.com'), findsNothing);

      serverManager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );
      await tester.pumpAndSettle();

      expect(find.text('https://api.example.com'), findsOneWidget);
    });

    testWidgets('tapping connected server navigates to lobby', (tester) async {
      final serverManager = _createServerManager();
      final entry = serverManager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );
      _loginEntry(entry);

      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      await tester.tap(find.text('https://api.example.com'));
      await tester.pumpAndSettle();

      expect(find.text('Lobby placeholder'), findsOneWidget);
    });

    testWidgets('tapping disconnected server navigates to home with url param',
        (tester) async {
      final serverManager = _createServerManager();
      serverManager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );

      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      await tester.tap(find.text('https://api.example.com'));
      await tester.pumpAndSettle();

      expect(_lastLocation, contains('url='));
      expect(
        _lastLocation,
        contains(Uri.encodeComponent('https://api.example.com')),
      );
    });

    testWidgets('connected server with requiresAuth shows Log out and delete',
        (tester) async {
      final serverManager = _createServerManager();
      final entry = serverManager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );
      _loginEntry(entry);

      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      expect(find.text('Log out'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('disconnected server shows only delete icon', (tester) async {
      final serverManager = _createServerManager();
      serverManager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );

      await tester.pumpWidget(_buildApp(serverManager: serverManager));
      await tester.pumpAndSettle();

      expect(find.text('Log out'), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('logout on native skips OIDC discovery', (tester) async {
      // `NativeAuthFlow.endSession` re-discovers via `discoveryUrl`
      // internally, so `_logout` must not pay for a redundant
      // pre-fetch. Pin both halves: probeClient is never called, and
      // `endSession` runs with `endSessionEndpoint: null`.
      final serverManager = _createServerManager();
      final entry = serverManager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );
      _loginEntry(entry);

      int probeRequests = 0;
      final probeClient = FakeHttpClient()
        ..onRequest = (method, uri) async {
          probeRequests++;
          return HttpResponse(statusCode: 200, bodyBytes: Uint8List(0));
        };

      final authFlow = RecordingAuthFlow();

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        authFlow: authFlow,
        probeClient: probeClient,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();

      expect(probeRequests, 0,
          reason: 'Native must not fetch discovery on logout.');
      expect(authFlow.endSessionCalled, isTrue);
      expect(authFlow.lastEndSessionEndpoint, isNull);
    });

    testWidgets('deleting a connected server logs out before removing',
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

      final authFlow = RecordingAuthFlow();

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        authFlow: authFlow,
        probeClient: probeClient,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Connected (1)'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(authFlow.endSessionCalled, isTrue);
      expect(serverManager.servers.value, isEmpty);
    });

    testWidgets('logout failure preserves session and surfaces error text',
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

      final authFlow = RecordingAuthFlow(
        endSessionError: Exception('idp unreachable'),
      );

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        authFlow: authFlow,
        probeClient: probeClient,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();

      expect(entry.auth.isAuthenticated, isTrue);
      expect(find.text('Connected (1)'), findsOneWidget);
      expect(find.textContaining('Log out failed:'), findsOneWidget);
      expect(find.textContaining('idp unreachable'), findsOneWidget);
    });

    testWidgets('delete-row logout failure preserves entry and shows error',
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

      final authFlow = RecordingAuthFlow(
        endSessionError: Exception('idp unreachable'),
      );

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        authFlow: authFlow,
        probeClient: probeClient,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(serverManager.servers.value, contains('test'));
      expect(entry.auth.isAuthenticated, isTrue);
      expect(find.textContaining('Log out failed'), findsOneWidget);
    });

    testWidgets('in-flight logout disables both Log out and delete',
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

      final blocker = Completer<void>();
      final authFlow = FakeAuthFlow()..endSessionCompleter = blocker;

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        authFlow: authFlow,
        probeClient: probeClient,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Log out'));
      // Pump enough for the discovery fetch to complete and endSession to be
      // awaiting the blocker; do not settle (the blocker future never
      // completes until we tell it to).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      // The Log out button now shows a spinner instead of text — find the
      // TextButton ancestor of the spinner to verify it's disabled.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final logoutButton = tester.widget<TextButton>(
        find.ancestor(
          of: find.byType(CircularProgressIndicator),
          matching: find.byType(TextButton),
        ),
      );
      expect(logoutButton.onPressed, isNull);

      final deleteButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_outline),
      );
      expect(deleteButton.onPressed, isNull);

      blocker.complete();
      await tester.pumpAndSettle();

      expect(entry.auth.isAuthenticated, isFalse);
    });

    testWidgets(
        'logout Error (non-Exception) shows generic message without type name',
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

      final authFlow = RecordingAuthFlow(
        onEndSession: () => throw _LogoutBoom(),
      );

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        authFlow: authFlow,
        probeClient: probeClient,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();

      expect(entry.auth.isAuthenticated, isTrue);
      expect(find.textContaining('Log out failed:'), findsOneWidget);
      expect(
        find.text('Log out failed: Sign-out failed. Please try again.'),
        findsOneWidget,
      );
      // Ensure no minified/raw runtime type name leaks (e.g. "(Nra)" or
      // "(_LogoutBoom)").
      expect(find.textContaining(RegExp(r'\(\w{3,}\)')), findsNothing);
    });

    testWidgets('logout on non-active session skips IdP round-trip',
        (tester) async {
      final serverManager = _createServerManager();
      serverManager.addServer(
        serverId: 'local',
        serverUrl: Uri.parse('http://localhost:8000'),
        requiresAuth: false,
      );

      final authFlow = RecordingAuthFlow();

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        authFlow: authFlow,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(authFlow.endSessionCalled, isFalse);
      expect(serverManager.servers.value, isEmpty);
    });
  });
}
