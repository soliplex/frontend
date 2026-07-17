import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;

import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/connect_flow.dart';
import 'package:soliplex_frontend/src/modules/auth/connection_probe.dart';
import 'package:soliplex_frontend/src/modules/auth/inactivity_logout_storage.dart';
import 'package:soliplex_frontend/src/modules/auth/platform/auth_flow.dart';
import 'package:soliplex_frontend/src/modules/auth/pre_auth_state.dart';
import 'package:soliplex_frontend/src/modules/auth/selected_server_storage.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';

import '../../helpers/fakes.dart';

const _provider = AuthProviderConfig(
  id: 'idp-1',
  name: 'Test IdP',
  serverUrl: 'https://auth.example.com',
  clientId: 'test-client',
  scope: 'openid email profile',
);

ServerManager _createManager() => ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );

ConnectFlow _createFlow({
  required FakeAuthFlow authFlow,
  InactivityLogoutFlagStorage? inactivityLogoutFlags,
  ServerManager? serverManager,
  DiscoverProviders? discover,
  void Function(Uri serverUrl)? onServerConnected,
}) =>
    ConnectFlow(
      serverManager: serverManager ?? _createManager(),
      probeClient: FakeHttpClient(),
      discover: discover ?? (_, __) async => [_provider],
      authFlow: authFlow,
      inactivityLogoutFlags:
          inactivityLogoutFlags ?? InMemoryInactivityLogoutFlagStorage(),
      onServerConnected: onServerConnected,
    );

AuthResult _successResult() => AuthResult(
      accessToken: 'access',
      refreshToken: 'refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConnectFlow.connect — returnTo plumbing', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'writes returnTo passed to connect() into PreAuthState',
      () async {
        final flow = _createFlow(
          authFlow: FakeAuthFlow()..throwRedirectInitiated = true,
        );

        await flow.connect(
          'https://server.example.com',
          returnTo: '/r/alias/room/thread/t1',
        );
        // _authenticate is invoked without await; pump the event queue so
        // its PreAuthStateStorage.save and AuthRedirectInitiated branch run.
        await pumpEventQueue();

        final saved = await PreAuthStateStorage.load();
        expect(saved, isNotNull);
        expect(saved!.frontendReturnTo, '/r/alias/room/thread/t1');
      },
    );

    test(
      'writes null frontendReturnTo when connect() is called without returnTo',
      () async {
        final flow = _createFlow(
          authFlow: FakeAuthFlow()..throwRedirectInitiated = true,
        );

        await flow.connect('https://server.example.com');
        await pumpEventQueue();

        final saved = await PreAuthStateStorage.load();
        expect(saved, isNotNull);
        expect(saved!.frontendReturnTo, isNull);
      },
    );
  });

  group('ConnectFlow._authenticate — forceLoginPrompt plumbing', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('passes forceLoginPrompt=true when the inactivity flag is marked',
        () async {
      final flags = InMemoryInactivityLogoutFlagStorage();
      final authFlow = FakeAuthFlow()..throwRedirectInitiated = true;
      final flow =
          _createFlow(authFlow: authFlow, inactivityLogoutFlags: flags);

      await flags.mark('https://server.example.com');

      await flow.connect('https://server.example.com');
      await pumpEventQueue();

      expect(authFlow.lastForceLoginPrompt, isTrue);
    });

    test('passes forceLoginPrompt=false when no flag is set', () async {
      final flags = InMemoryInactivityLogoutFlagStorage();
      final authFlow = FakeAuthFlow()..throwRedirectInitiated = true;
      final flow =
          _createFlow(authFlow: authFlow, inactivityLogoutFlags: flags);

      await flow.connect('https://server.example.com');
      await pumpEventQueue();

      expect(authFlow.lastForceLoginPrompt, isFalse);
    });

    test('isMarked does not clear the flag on its own', () async {
      final flags = InMemoryInactivityLogoutFlagStorage();
      final authFlow = FakeAuthFlow()..throwRedirectInitiated = true;
      final flow =
          _createFlow(authFlow: authFlow, inactivityLogoutFlags: flags);

      await flags.mark('https://server.example.com');

      await flow.connect('https://server.example.com');
      await pumpEventQueue();

      // The web flow throws AuthRedirectInitiated before any clear can
      // happen, so the flag must still be set when the browser returns.
      expect(await flags.isMarked('https://server.example.com'), isTrue);
    });

    test('successful authentication clears the flag', () async {
      final flags = InMemoryInactivityLogoutFlagStorage();
      final authFlow = FakeAuthFlow()..nextResult = _successResult();
      final flow =
          _createFlow(authFlow: authFlow, inactivityLogoutFlags: flags);

      await flags.mark('https://server.example.com');

      await flow.connect('https://server.example.com');
      await pumpEventQueue();

      expect(authFlow.lastForceLoginPrompt, isTrue);
      expect(await flags.isMarked('https://server.example.com'), isFalse);
    });

    test('cancelled IdP challenge keeps the flag set for the next retry',
        () async {
      final flags = InMemoryInactivityLogoutFlagStorage();
      final authFlow = FakeAuthFlow()
        ..nextError = const AuthException(
          'User cancelled',
          kind: AuthFailureKind.cancelled,
        );
      final flow =
          _createFlow(authFlow: authFlow, inactivityLogoutFlags: flags);

      await flags.mark('https://server.example.com');

      await flow.connect('https://server.example.com');
      await pumpEventQueue();

      // The cancel keeps the flag set so a retry also forces prompt=login
      // — otherwise an attacker could cancel once and then sign in via
      // silent SSO.
      expect(await flags.isMarked('https://server.example.com'), isTrue);
    });
  });

  group('ConnectFlow — selected-server persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('persists the connected server after OIDC success', () async {
      final manager = _createManager();
      final flow = _createFlow(
        authFlow: FakeAuthFlow()..nextResult = _successResult(),
        serverManager: manager,
      );

      await flow.connect('https://server.example.com');
      await pumpEventQueue();

      expect(
        await SelectedServerStorage.load(),
        manager.servers.value.keys.single,
      );
    });

    test('persists the connected server when no auth is required', () async {
      final manager = _createManager();
      final flow = _createFlow(
        authFlow: FakeAuthFlow(),
        serverManager: manager,
        discover: (_, __) async => [],
      );

      await flow.connect('https://server.example.com');
      await pumpEventQueue();

      expect(
        await SelectedServerStorage.load(),
        manager.servers.value.keys.single,
      );
    });
  });

  group('ConnectFlow — onServerConnected', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('fires once with the server URL after an OIDC login', () async {
      final manager = _createManager();
      Uri? connected;
      var calls = 0;
      final flow = _createFlow(
        authFlow: FakeAuthFlow()..nextResult = _successResult(),
        serverManager: manager,
        onServerConnected: (url) {
          connected = url;
          calls++;
        },
      );

      await flow.connect('https://server.example.com');
      await pumpEventQueue();

      expect(calls, 1);
      expect(
        connected.toString(),
        manager.servers.value.values.single.serverUrl.toString(),
      );
    });

    test('fires when a no-auth server is added', () async {
      var calls = 0;
      final flow = _createFlow(
        authFlow: FakeAuthFlow(),
        discover: (_, __) async => [],
        onServerConnected: (_) => calls++,
      );

      await flow.connect('https://server.example.com');
      await pumpEventQueue();

      expect(calls, 1);
    });
  });
}
