import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';

void main() {
  group('AuthTokens', () {
    test('an empty ID token is absent', () {
      final tokens = AuthTokens(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.utc(2030),
        idToken: '',
      );

      expect(tokens.idToken, isNull);
    });

    test('an empty stored ID token is absent', () {
      final tokens = AuthTokens.fromJson({
        'accessToken': 'a',
        'refreshToken': 'r',
        'expiresAt': '2030-01-01T00:00:00.000Z',
        'idToken': '',
      });

      expect(tokens.idToken, isNull);
    });

    test('a non-empty ID token is kept', () {
      final tokens = AuthTokens(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.utc(2030),
        idToken: 'id-1',
      );

      expect(tokens.idToken, 'id-1');
    });
  });
}
