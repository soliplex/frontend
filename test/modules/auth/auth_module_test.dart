import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/interfaces/auth_state.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';

import '../../helpers/fakes.dart';

const _provider = OidcProvider(
  discoveryUrl: 'https://auth.example.com/.well-known/openid-configuration',
  clientId: 'test-client',
);

ServerManager _createManager() {
  return ServerManager(
    refreshClient: FakeHttpClient(),
    inspector: FakeHttpObserver(),
    storage: InMemoryTokenStorage(),
  );
}

void main() {
  group('authModule', () {
    test('authState reflects server auth changes', () {
      final manager = _createManager();
      expect(manager.authState.value, isA<Unauthenticated>());

      final entry = manager.addServer(
        serverId: 'test',
        serverUrl: Uri.parse('https://api.example.com'),
      );
      entry.auth.login(
        provider: _provider,
        tokens: AuthTokens(
          accessToken: 'access',
          refreshToken: 'refresh',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );

      expect(manager.authState.value, isA<Authenticated>());

      entry.auth.logout();
      expect(manager.authState.value, isA<Unauthenticated>());
    });
  });
}
