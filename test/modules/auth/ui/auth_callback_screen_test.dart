import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_providers.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/default_backend_url.dart';
import 'package:soliplex_frontend/src/modules/auth/inactivity_logout_storage.dart';
import 'package:soliplex_frontend/src/modules/auth/platform/callback_params.dart';
import 'package:soliplex_frontend/src/modules/auth/pre_auth_state.dart';
import 'package:soliplex_frontend/src/modules/auth/selected_server_storage.dart';
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
  PreAuthStateStorage? preAuthStateStorage,
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
      if (preAuthStateStorage != null)
        preAuthStateStorageProvider.overrideWithValue(preAuthStateStorage),
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

    testWidgets('shows error when the callback query could not be read',
        (tester) async {
      final serverManager = _createServerManager();
      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        callbackParams: const WebCallbackMalformed(),
      ));
      await tester.pumpAndSettle();

      expect(
          find.text('The sign-in response could not be read. '
              'Please try again.'),
          findsOneWidget);
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
      await const LocalPreAuthStateStorage().save(state);

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

    testWidgets('a failed pre-auth clear still completes the sign-in',
        (tester) async {
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));
      final serverManager = _createServerManager();

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        callbackParams: const WebCallbackSuccess(
          accessToken: 'access',
          refreshToken: 'refresh',
          expiresIn: 3600,
        ),
        preAuthStateStorage: InMemoryPreAuthStateStorage(failClear: true)
          ..saved = _validPreAuthState(),
      ));
      await tester.pumpAndSettle();

      expect(serverManager.servers.value, isNotEmpty);
      expect(find.text('Lobby Screen'), findsOneWidget);
      expect(
        sink.records.where((r) =>
            r.loggerName == 'soliplex.pre_auth_state' &&
            r.level == LogLevel.warning),
        hasLength(1),
      );
    });

    testWidgets('a failure carrying a callback value logs only its shape',
        (tester) async {
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));
      await const LocalPreAuthStateStorage().save(_validPreAuthState());

      // An `expires_in` past DateTime's range makes the expiry throw a
      // RangeError whose text carries a value derived from the link.
      await tester.pumpWidget(_buildApp(
        serverManager: _createServerManager(),
        callbackParams: const WebCallbackSuccess(
          accessToken: 'access',
          expiresIn: 9000000000000,
        ),
      ));
      await tester.pumpAndSettle();

      expect(
          find.text('Something went wrong. Please try again.'), findsOneWidget);
      final record = sink.records.singleWhere((r) =>
          r.loggerName == 'soliplex.auth_callback_screen' &&
          r.level == LogLevel.error);
      expect(record.error, isNull);
      expect(
          record.attributes['failure'], 'RangeError: millisecondsSinceEpoch');
      expect(record.stackTrace, isNotNull);
    });

    testWidgets('persists the connected server as the selection',
        (tester) async {
      const serverId = 'https://api.example.com';
      final serverManager = _createServerManager();
      await const LocalPreAuthStateStorage().save(_validPreAuthState());

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        callbackParams: const WebCallbackSuccess(
          accessToken: 'access',
          refreshToken: 'refresh',
          expiresIn: 3600,
        ),
      ));
      await tester.pumpAndSettle();

      expect(await SelectedServerStorage.load(), serverId);
    });

    testWidgets('persists the connected backend url as the default',
        (tester) async {
      final serverManager = _createServerManager();
      await const LocalPreAuthStateStorage().save(_validPreAuthState());

      await tester.pumpWidget(_buildApp(
        serverManager: serverManager,
        callbackParams: const WebCallbackSuccess(
          accessToken: 'access',
          refreshToken: 'refresh',
          expiresIn: 3600,
        ),
      ));
      await tester.pumpAndSettle();

      expect(await DefaultBackendUrlStorage.load(), 'https://api.example.com');
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
      await const LocalPreAuthStateStorage().save(state);

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

    testWidgets('tampered storage with an unsafe frontendReturnTo is rejected',
        (tester) async {
      // Defense in depth: even if shared_preferences is tampered with
      // externally (the constructor would otherwise reject these),
      // load() must not propagate a value the callback can't safely
      // navigate to.
      for (final crafted in [
        'https://evil.com/x',
        'http://evil.com/x',
        '//evil.com/x',
        '/lobby?server=%FF',
        '/auth/callback',
      ]) {
        SharedPreferences.setMockInitialValues({
          LocalPreAuthStateStorage.storageKey: _rawPreAuthJson(
            frontendReturnTo: crafted,
          ),
        });
        final serverManager = _createServerManager();

        // A fresh screen per case, so its error text is this case's.
        await tester.pumpWidget(const SizedBox());
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
          find.text(
            'Authentication session expired or missing. Please try again.',
          ),
          findsOneWidget,
          reason: 'crafted=$crafted should surface the session error',
        );
        expect(serverManager.servers.value, isEmpty, reason: crafted);
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString(LocalPreAuthStateStorage.storageKey),
          isNull,
          reason: 'crafted=$crafted should be cleared from storage',
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
      await const LocalPreAuthStateStorage().save(state);

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
      await const LocalPreAuthStateStorage().save(state);

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
      await const LocalPreAuthStateStorage().save(_validPreAuthState());

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
