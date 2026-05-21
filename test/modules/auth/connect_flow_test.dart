import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/connect_flow.dart';
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

ConnectFlow _createFlow({required FakeAuthFlow authFlow}) => ConnectFlow(
      serverManager: _createManager(),
      probeClient: FakeHttpClient(),
      discover: (_, __) async => [_provider],
      authFlow: authFlow,
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
}
