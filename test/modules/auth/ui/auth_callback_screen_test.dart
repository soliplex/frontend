import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_providers.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/inactivity_logout_storage.dart';
import 'package:soliplex_frontend/src/modules/auth/platform/callback_params.dart';
import 'package:soliplex_frontend/src/modules/auth/pre_auth_state.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/auth/ui/auth_callback_screen.dart';

import '../../../helpers/fakes.dart';

String _rawPreAuthJson({required String frontendReturnTo}) => jsonEncode({
      'serverUrl': 'https://api.example.com',
      'providerId': 'keycloak',
      'discoveryUrl':
          'https://sso.example.com/.well-known/openid-configuration',
      'clientId': 'soliplex',
      'createdAt': DateTime.timestamp().toUtc().toIso8601String(),
      'frontendReturnTo': frontendReturnTo,
    });

ServerManager _createServerManager() => ServerManager(
      authFactory: () => AuthSession(
        refreshService: FakeTokenRefreshService(),
      ),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

Widget _buildApp({
  required ServerManager serverManager,
  required CallbackParams callbackParams,
  InactivityLogoutFlagStorage? inactivityFlags,
}) {
  final router = GoRouter(
    initialLocation: '/auth/callback',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(
          body: Center(child: Text('Home Screen')),
        ),
      ),
      GoRoute(
        path: '/lobby',
        builder: (_, __) => const Scaffold(
          body: Center(child: Text('Lobby Screen')),
        ),
      ),
      GoRoute(
        path: '/room/:serverAlias/:roomId',
        builder: (_, state) => Scaffold(
          body: Center(
            child: Text(
              'Room ${state.pathParameters['serverAlias']}/'
              '${state.pathParameters['roomId']}',
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/auth/callback',
        builder: (_, __) => AuthCallbackScreen(serverManager: serverManager),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authFlowProvider.overrideWithValue(FakeAuthFlow()),
      callbackParamsProvider.overrideWithValue(callbackParams),
      inactivityLogoutFlagsProvider.overrideWithValue(
          inactivityFlags ?? InMemoryInactivityLogoutFlagStorage()),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

PreAuthState _validPreAuthState() => PreAuthState(
      serverUrl: Uri.parse('https://api.example.com'),
      providerId: 'keycloak',
      discoveryUrl: 'https://sso.example.com/.well-known/openid-configuration',
      clientId: 'soliplex',
      createdAt: DateTime.timestamp(),
    );

void main() {
  group('AuthCallbackScreen', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('shows error when no callback params', (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        callbackParams: const NoCallbackParams(),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('No callback'), findsOneWidget);
      expect(find.text('Back to home'), findsOneWidget);
    });

    testWidgets('shows error when callback has error', (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        callbackParams: const WebCallbackError(
          error: 'access_denied',
          errorDescription: 'User denied access',
        ),
      ));
      await tester.pumpAndSettle();

      expect(
        find.text('The identity provider rejected the sign-in request.'),
        findsOneWidget,
      );
      expect(find.textContaining('access_denied'), findsNothing);
    });

    testWidgets('shows friendly message for invalid_grant error',
        (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        callbackParams: const WebCallbackError(error: 'invalid_grant'),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('expired'), findsOneWidget);
      expect(find.textContaining('invalid_grant'), findsNothing);
    });

    testWidgets('shows generic message for unknown OAuth error code',
        (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        callbackParams: const WebCallbackError(error: 'some_unknown_code'),
      ));
      await tester.pumpAndSettle();

      expect(
        find.text('Sign-in was rejected. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('some_unknown_code'), findsNothing);
    });

    testWidgets('shows error when no pre-auth state saved', (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        callbackParams: const WebCallbackSuccess(
          accessToken: 'access',
          refreshToken: 'refresh',
          expiresIn: 3600,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('expired'), findsOneWidget);
    });

    testWidgets('adds server and navigates to lobby on valid callback',
        (tester) async {
      final serverManager = _createServerManager();
      final state = _validPreAuthState();
      await PreAuthStateStorage.save(state);

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        callbackParams: const WebCallbackSuccess(
          accessToken: 'access',
          refreshToken: 'refresh',
          expiresIn: 3600,
        ),
      ));
      await tester.pumpAndSettle();

      expect(serverManager.servers.value, isNotEmpty);
      expect(find.text('Lobby Screen'), findsOneWidget);
    });

    testWidgets('navigates to frontendReturnTo when set', (tester) async {
      final serverManager = _createServerManager();
      final state = PreAuthState(
        serverUrl: Uri.parse('https://api.example.com'),
        providerId: 'keycloak',
        discoveryUrl:
            'https://sso.example.com/.well-known/openid-configuration',
        clientId: 'soliplex',
        createdAt: DateTime.timestamp(),
        frontendReturnTo: '/room/server-a/r1',
      );
      await PreAuthStateStorage.save(state);

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        callbackParams: const WebCallbackSuccess(
          accessToken: 'access',
          refreshToken: 'refresh',
          expiresIn: 3600,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Room server-a/r1'), findsOneWidget);
      expect(find.text('Lobby Screen'), findsNothing);
    });

    testWidgets('tampered storage with absolute frontendReturnTo is rejected',
        (tester) async {
      // Defense in depth: even if shared_preferences is tampered with
      // externally (the constructor would otherwise reject these),
      // load() must not propagate a value that could open-redirect
      // the user.
      for (final crafted in [
        'https://evil.com/x',
        'http://evil.com/x',
        '//evil.com/x',
      ]) {
        SharedPreferences.setMockInitialValues({
          PreAuthStateStorage.storageKey: _rawPreAuthJson(
            frontendReturnTo: crafted,
          ),
        });
        final serverManager = _createServerManager();

        await tester.pumpWidget(_buildApp(
          serverManager: serverManager,
          callbackParams: const WebCallbackSuccess(
            accessToken: 'access',
            refreshToken: 'refresh',
            expiresIn: 3600,
          ),
        ));
        await tester.pumpAndSettle();

        expect(
          find.text('Room ${crafted.replaceAll('/', '')}'),
          findsNothing,
          reason: 'crafted=$crafted must not navigate to the attacker target',
        );
        expect(
          find.text('Lobby Screen'),
          findsNothing,
          reason: 'crafted=$crafted should surface the error, not silently '
              'land on the lobby',
        );
      }
    });

    testWidgets('shows error when pre-auth state is expired', (tester) async {
      final serverManager = _createServerManager();
      final state = PreAuthState(
        serverUrl: Uri.parse('https://api.example.com'),
        providerId: 'keycloak',
        discoveryUrl:
            'https://sso.example.com/.well-known/openid-configuration',
        clientId: 'soliplex',
        createdAt: DateTime.timestamp().subtract(const Duration(minutes: 31)),
      );
      await PreAuthStateStorage.save(state);

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        callbackParams: const WebCallbackSuccess(
          accessToken: 'access',
          refreshToken: 'refresh',
          expiresIn: 3600,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('expired'), findsOneWidget);
    });

    testWidgets('logs into existing server without crashing', (tester) async {
      final serverManager = _createServerManager();
      serverManager.addServer(
        serverId: 'https://api.example.com',
        serverUrl: Uri.parse('https://api.example.com'),
      );

      final state = _validPreAuthState();
      await PreAuthStateStorage.save(state);

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        callbackParams: const WebCallbackSuccess(
          accessToken: 'access',
          refreshToken: 'refresh',
          expiresIn: 3600,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Lobby Screen'), findsOneWidget);
      final entry = serverManager.servers.value['https://api.example.com']!;
      expect(entry.isConnected, isTrue);
    });

    testWidgets('clears the inactivity flag on a successful callback',
        (tester) async {
      const serverId = 'https://api.example.com';
      final flags = InMemoryInactivityLogoutFlagStorage()..marked.add(serverId);
      final serverManager = _createServerManager();
      await PreAuthStateStorage.save(_validPreAuthState());

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        callbackParams: const WebCallbackSuccess(
          accessToken: 'access',
          refreshToken: 'refresh',
          expiresIn: 3600,
        ),
        inactivityFlags: flags,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Lobby Screen'), findsOneWidget);
      expect(flags.clearLog, contains(serverId));
      expect(flags.marked, isNot(contains(serverId)));
    });

    testWidgets('keeps the inactivity flag when the callback fails',
        (tester) async {
      // No pre-auth state saved → callback fails before login. The flag
      // must survive so the next attempt still forces prompt=login.
      const serverId = 'https://api.example.com';
      final flags = InMemoryInactivityLogoutFlagStorage()..marked.add(serverId);
      final serverManager = _createServerManager();

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        callbackParams: const WebCallbackSuccess(
          accessToken: 'access',
          refreshToken: 'refresh',
          expiresIn: 3600,
        ),
        inactivityFlags: flags,
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('expired'), findsOneWidget);
      expect(flags.clearLog, isEmpty);
      expect(flags.marked, contains(serverId));
    });

    testWidgets('back to home button navigates to /', (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        callbackParams: const NoCallbackParams(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Back to home'));
      await tester.pumpAndSettle();

      expect(find.text('Home Screen'), findsOneWidget);
    });
  });
}
