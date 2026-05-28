import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show AuthProviderConfig;

import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/connect_flow.dart';
import 'package:soliplex_frontend/src/modules/auth/platform/auth_flow.dart';
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

ConnectFlow _createFlow({required FakeAuthFlow authFlow}) => ConnectFlow(
      serverManager: _createManager(),
      probeClient: FakeHttpClient(),
      discover: (_, __) async => [_provider],
      authFlow: authFlow,
      inactivityLogoutFlags: InMemoryInactivityLogoutFlagStorage(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConnectFlow._authenticate — AuthException routing', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'cancelled → ConnectNotice (not ConnectError), text is cancel message',
      () async {
        final flow = _createFlow(
          authFlow: FakeAuthFlow()
            ..nextError = const AuthException(
              'User cancelled',
              kind: AuthFailureKind.cancelled,
            ),
        );

        await flow.connect('https://server.example.com');
        await pumpEventQueue();

        final s = flow.state.value as UrlInput;
        final m = s.message;
        expect(m, isA<ConnectNotice>());
        expect((m as ConnectNotice).text, 'Sign-in was cancelled.');
      },
    );

    test(
      'idpRejected with access_denied → ConnectError, text says rejected, '
      'raw oauthError not exposed',
      () async {
        final flow = _createFlow(
          authFlow: FakeAuthFlow()
            ..nextError = const AuthException(
              'IdP rejected: access_denied',
              kind: AuthFailureKind.idpRejected,
              oauthError: 'access_denied',
            ),
        );

        await flow.connect('https://server.example.com');
        await pumpEventQueue();

        final s = flow.state.value as UrlInput;
        final m = s.message;
        expect(m, isA<ConnectError>());
        final text = (m as ConnectError).text;
        expect(text, contains('rejected the sign-in'));
        expect(text, isNot(contains('access_denied')));
      },
    );

    test(
      'unknown (generic Exception) → ConnectError, no Exception interpolation '
      'or raw error code leak',
      () async {
        final flow = _createFlow(
          authFlow: FakeAuthFlow()
            ..nextError = const AuthException(
              'Something unexpected (Nra).',
              kind: AuthFailureKind.unknown,
            ),
        );

        await flow.connect('https://server.example.com');
        await pumpEventQueue();

        final s = flow.state.value as UrlInput;
        final m = s.message;
        expect(m, isA<ConnectError>());
        final text = (m as ConnectError).text;
        expect(text, isNot(matches(RegExp(r'\(\w{3,4}\)\.'))));
        expect(text, isNot(contains('Exception')));
      },
    );

    test(
      'discoveryUnreachable → ConnectError mentioning the probed server URL',
      () async {
        final flow = _createFlow(
          authFlow: FakeAuthFlow()
            ..nextError = const AuthException(
              'Discovery doc unreachable',
              kind: AuthFailureKind.discoveryUnreachable,
            ),
        );

        await flow.connect('https://server.example.com');
        await pumpEventQueue();

        final s = flow.state.value as UrlInput;
        final m = s.message;
        expect(m, isA<ConnectError>());
        expect((m as ConnectError).text, contains('server.example.com'));
      },
    );
  });
}
