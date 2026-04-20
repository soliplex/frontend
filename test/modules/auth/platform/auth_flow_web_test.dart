@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;
import 'package:soliplex_frontend/src/modules/auth/platform/auth_flow.dart';
import 'package:soliplex_frontend/src/modules/auth/platform/auth_flow_web.dart';

const _provider = AuthProviderConfig(
  id: 'keycloak',
  name: 'Keycloak',
  serverUrl: 'https://sso.example.com/realms/app',
  clientId: 'soliplex',
  scope: 'openid email profile',
);

class FakeUrlNavigator implements UrlNavigator {
  String? lastNavigatedUrl;

  @override
  String get origin => 'https://app.example.com';

  @override
  void navigateTo(String url) {
    lastNavigatedUrl = url;
  }
}

void main() {
  group('WebAuthFlow', () {
    late FakeUrlNavigator navigator;
    late WebAuthFlow authFlow;

    setUp(() {
      navigator = FakeUrlNavigator();
      authFlow = WebAuthFlow(navigator: navigator);
    });

    test('authenticate builds correct BFF login URL with backendUrl', () async {
      expect(
        () => authFlow.authenticate(
          _provider,
          backendUrl: Uri.parse('https://api.example.com'),
        ),
        throwsA(isA<AuthRedirectInitiated>()),
      );

      expect(navigator.lastNavigatedUrl, isNotNull);
      expect(
        navigator.lastNavigatedUrl,
        startsWith('https://api.example.com/api/login/keycloak?return_to='),
      );
    });

    test(
      'authenticate falls back to same origin when backendUrl is null',
      () async {
        expect(
          () => authFlow.authenticate(_provider),
          throwsA(isA<AuthRedirectInitiated>()),
        );

        expect(
          navigator.lastNavigatedUrl,
          startsWith('https://app.example.com/api/login/keycloak?return_to='),
        );
      },
    );

    test('authenticate includes return_to with callback path', () async {
      expect(
        () => authFlow.authenticate(_provider),
        throwsA(isA<AuthRedirectInitiated>()),
      );

      expect(navigator.lastNavigatedUrl, contains('return_to='));
      expect(navigator.lastNavigatedUrl, contains('/auth/callback'));
    });

    test('endSession redirects to IdP logout endpoint', () async {
      await authFlow.endSession(
        discoveryUrl:
            'https://sso.example.com/.well-known/openid-configuration',
        endSessionEndpoint: 'https://sso.example.com/logout',
        idToken: 'my_id_token',
        clientId: 'soliplex',
      );

      expect(navigator.lastNavigatedUrl, isNotNull);
      final uri = Uri.parse(navigator.lastNavigatedUrl!);
      expect(uri.host, 'sso.example.com');
      expect(uri.path, '/logout');
      expect(
        uri.queryParameters['post_logout_redirect_uri'],
        'https://app.example.com',
      );
      expect(uri.queryParameters['client_id'], 'soliplex');
      expect(uri.queryParameters['id_token_hint'], 'my_id_token');
    });

    test('endSession preserves existing query params on endpoint', () async {
      await authFlow.endSession(
        discoveryUrl:
            'https://sso.example.com/.well-known/openid-configuration',
        endSessionEndpoint: 'https://sso.example.com/logout?tenant=xyz',
        idToken: 'my_id_token',
        clientId: 'soliplex',
      );

      final uri = Uri.parse(navigator.lastNavigatedUrl!);
      expect(uri.queryParameters['tenant'], 'xyz');
      expect(uri.queryParameters['client_id'], 'soliplex');
    });

    test('endSession does nothing when endSessionEndpoint is null', () async {
      await authFlow.endSession(
        discoveryUrl:
            'https://sso.example.com/.well-known/openid-configuration',
        endSessionEndpoint: null,
        idToken: 'my_id_token',
        clientId: 'soliplex',
      );

      expect(navigator.lastNavigatedUrl, isNull);
    });

    test('endSession omits id_token_hint when idToken is empty', () async {
      await authFlow.endSession(
        discoveryUrl:
            'https://sso.example.com/.well-known/openid-configuration',
        endSessionEndpoint: 'https://sso.example.com/logout',
        idToken: '',
        clientId: 'soliplex',
      );

      final uri = Uri.parse(navigator.lastNavigatedUrl!);
      expect(uri.queryParameters.containsKey('id_token_hint'), isFalse);
    });
  });
}
