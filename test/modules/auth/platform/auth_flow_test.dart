import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/auth/platform/auth_flow.dart';

void main() {
  group('AuthException', () {
    test('toString includes kind and message', () {
      const error = AuthException(
        'something failed',
        kind: AuthFailureKind.unknown,
      );
      expect(
        error.toString(),
        'AuthException(AuthFailureKind.unknown): something failed',
      );
    });

    test('toString includes oauthError when present', () {
      const error = AuthException(
        'IdP rejected',
        kind: AuthFailureKind.idpRejected,
        oauthError: 'access_denied',
      );
      expect(
        error.toString(),
        'AuthException(AuthFailureKind.idpRejected, oauthError: access_denied): IdP rejected',
      );
    });
  });

  group('AuthRedirectInitiated', () {
    test('toString describes redirect', () {
      const error = AuthRedirectInitiated();
      expect(error.toString(), contains('redirecting'));
    });
  });

  // WebAuthFlow tests require `--platform chrome` since they import
  // package:web. They live in test/modules/auth/platform/auth_flow_web_test.dart.
}
