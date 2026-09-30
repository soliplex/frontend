import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';

void main() {
  group('AuthTokens', () {
    test('an empty stored ID token is absent', () {
      final tokens = AuthTokens.fromJson({
        'accessToken': 'a',
        'refreshToken': 'r',
        'expiresAt': '2030-01-01T00:00:00.000Z',
        'idToken': '',
      });

      expect(tokens.idToken, isNull);
    });
  });
}
