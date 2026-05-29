import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;

import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/connect_flow.dart';
import 'package:soliplex_frontend/src/modules/auth/inactivity_logout_storage.dart';
import 'package:soliplex_frontend/src/modules/auth/platform/auth_flow.dart';
import 'package:soliplex_frontend/src/modules/auth/pre_auth_state.dart';
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
}) =>
    ConnectFlow(
      serverManager: _createManager(),
      probeClient: FakeHttpClient(),
      discover: (_, __) async => [_provider],
      authFlow: authFlow,
      inactivityLogoutFlags:
          inactivityLogoutFlags ?? InMemoryInactivityLogoutFlagStorage(),
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

    AuthResult successResult() => AuthResult(
          accessToken: 'access',
          refreshToken: 'refresh',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        );

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
      final authFlow = FakeAuthFlow()..nextResult = successResult();
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
}
