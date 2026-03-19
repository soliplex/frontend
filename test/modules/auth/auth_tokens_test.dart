import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';

void main() {
  group('OidcProvider', () {
    test('toJson/fromJson round-trip', () {
      const original = OidcProvider(
        discoveryUrl:
            'https://auth.example.com/.well-known/openid-configuration',
        clientId: 'my-client',
      );

      final json = original.toJson();
      final restored = OidcProvider.fromJson(json);

      expect(restored.discoveryUrl, original.discoveryUrl);
      expect(restored.clientId, original.clientId);
    });
  });

  group('AuthTokens', () {
    final expiresAt = DateTime.utc(2026, 1, 1, 12);

    test('toJson/fromJson round-trip', () {
      final original = AuthTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: expiresAt,
        idToken: 'id-tok',
      );

      final json = original.toJson();
      final restored = AuthTokens.fromJson(json);

      expect(restored.accessToken, original.accessToken);
      expect(restored.refreshToken, original.refreshToken);
      expect(restored.expiresAt, original.expiresAt);
      expect(restored.idToken, original.idToken);
    });

    test('toJson/fromJson round-trip without idToken', () {
      final original = AuthTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: expiresAt,
      );

      final json = original.toJson();
      final restored = AuthTokens.fromJson(json);

      expect(restored.idToken, isNull);
    });
  });
}
