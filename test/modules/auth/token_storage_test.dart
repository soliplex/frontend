import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/token_storage.dart';

import '../../helpers/fakes.dart';

const _provider = OidcProvider(
  discoveryUrl: 'https://auth.example.com/.well-known/openid-configuration',
  clientId: 'test-client',
);

final _tokens = AuthTokens(
  accessToken: 'access',
  refreshToken: 'refresh',
  expiresAt: DateTime.utc(2026, 1, 1, 12),
  idToken: 'id-tok',
);

void main() {
  group('PersistedServer', () {
    test('toJson/fromJson round-trip', () {
      final original = PersistedServer(
        serverUrl: Uri.parse('https://api.example.com'),
        provider: _provider,
        tokens: _tokens,
      );

      final json = original.toJson();
      final restored = PersistedServer.fromJson(json);

      expect(restored.serverUrl, original.serverUrl);
      expect(restored.provider.discoveryUrl, original.provider.discoveryUrl);
      expect(restored.provider.clientId, original.provider.clientId);
      expect(restored.tokens.accessToken, original.tokens.accessToken);
      expect(restored.tokens.refreshToken, original.tokens.refreshToken);
      expect(restored.tokens.expiresAt, original.tokens.expiresAt);
      expect(restored.tokens.idToken, original.tokens.idToken);
    });
  });

  group('InMemoryTokenStorage', () {
    late InMemoryTokenStorage storage;

    setUp(() {
      storage = InMemoryTokenStorage();
    });

    test('loadAll returns empty map initially', () async {
      final result = await storage.loadAll();
      expect(result, isEmpty);
    });

    test('save and loadAll', () async {
      final server = PersistedServer(
        serverUrl: Uri.parse('https://api.example.com'),
        provider: _provider,
        tokens: _tokens,
      );

      await storage.save('server-1', server);

      final result = await storage.loadAll();
      expect(result, hasLength(1));
      expect(result['server-1']!.serverUrl, server.serverUrl);
    });

    test('save overwrites existing entry', () async {
      final server1 = PersistedServer(
        serverUrl: Uri.parse('https://api1.example.com'),
        provider: _provider,
        tokens: _tokens,
      );
      final server2 = PersistedServer(
        serverUrl: Uri.parse('https://api2.example.com'),
        provider: _provider,
        tokens: _tokens,
      );

      await storage.save('server-1', server1);
      await storage.save('server-1', server2);

      final result = await storage.loadAll();
      expect(result, hasLength(1));
      expect(
          result['server-1']!.serverUrl, Uri.parse('https://api2.example.com'));
    });

    test('delete removes entry', () async {
      final server = PersistedServer(
        serverUrl: Uri.parse('https://api.example.com'),
        provider: _provider,
        tokens: _tokens,
      );

      await storage.save('server-1', server);
      await storage.delete('server-1');

      final result = await storage.loadAll();
      expect(result, isEmpty);
    });

    test('delete is no-op for missing key', () async {
      await storage.delete('nonexistent');
      final result = await storage.loadAll();
      expect(result, isEmpty);
    });

    test('loadAll returns unmodifiable map', () async {
      final server = PersistedServer(
        serverUrl: Uri.parse('https://api.example.com'),
        provider: _provider,
        tokens: _tokens,
      );

      await storage.save('server-1', server);

      final result = await storage.loadAll();
      expect(
        () => (result as Map)['new-key'] = server,
        throwsUnsupportedError,
      );
    });
  });
}
