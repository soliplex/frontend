import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/auth/user_claims.dart';

import '../../helpers/test_server_entry.dart';

void main() {
  group('decodeJwtClaims', () {
    test('returns the payload of a well-formed token', () {
      expect(decodeJwtClaims(testJwt({'sub': 'u', 'email': 'a@b'})),
          {'sub': 'u', 'email': 'a@b'});
    });

    test('returns null for an undecodable payload segment', () {
      expect(decodeJwtClaims('aaa.!!!not-base64!!!.sig'), isNull);
    });
  });

  group('identityFromClaims', () {
    test('joins iss and sub', () {
      expect(
        identityFromClaims({'iss': 'https://idp.example/realm', 'sub': 'u-1'}),
        'https://idp.example/realm#u-1',
      );
    });

    test('returns null when iss is missing', () {
      expect(identityFromClaims({'sub': 'u-1'}), isNull);
    });

    test('returns null when a claim is blank or not a string', () {
      expect(identityFromClaims({'iss': '', 'sub': 'u-1'}), isNull);
      expect(identityFromClaims({'iss': 'i', 'sub': 7}), isNull);
      expect(identityFromClaims({'iss': 'i', 'sub': ''}), isNull);
    });
  });

  group('accountFromClaims', () {
    test('prefers the full name from given + family', () {
      final account = accountFromClaims({
        'given_name': 'Ada',
        'family_name': 'Lovelace',
        'preferred_username': 'ada',
        'email': 'ada@example.com',
      });
      expect(account.name, 'Ada Lovelace');
      expect(account.email, 'ada@example.com');
    });

    test('uses a lone given (or family) name, trimmed', () {
      final account =
          accountFromClaims({'given_name': 'Ada', 'family_name': ''});
      expect(account.name, 'Ada');
      expect(account.email, isNull);
    });

    test('uses email as the name but drops the duplicate email line', () {
      final account = accountFromClaims({'email': 'ada@example.com'});
      expect(account.name, 'ada@example.com');
      expect(account.email, isNull);
    });

    test('drops the email line when it is also the preferred_username', () {
      final account = accountFromClaims({
        'preferred_username': 'ada@example.com',
        'email': 'ada@example.com',
      });
      expect(account.name, 'ada@example.com');
      expect(account.email, isNull);
    });

    test('treats whitespace-only name fields as absent', () {
      final account = accountFromClaims({
        'given_name': '  ',
        'family_name': '',
        'preferred_username': 'ada',
      });
      expect(account.name, 'ada');
    });

    test('treats a whitespace-only preferred_username as absent', () {
      final account = accountFromClaims({
        'preferred_username': '  ',
        'email': 'ada@example.com',
      });
      expect(account.name, 'ada@example.com');
    });

    test('treats a whitespace-only email as null', () {
      final account =
          accountFromClaims({'preferred_username': 'ada', 'email': '  '});
      expect(account.email, isNull);
    });

    test('treats a non-string field as absent without discarding siblings', () {
      // A malformed claim (here a numeric given_name) must not take down the
      // valid preferred_username and email alongside it.
      final account = accountFromClaims({
        'given_name': 123,
        'preferred_username': 'ada',
        'email': 'ada@example.com',
      });
      expect(account.name, 'ada');
      expect(account.email, 'ada@example.com');
    });

    test('null claims give the generic label', () {
      expect(accountFromClaims(null), (name: signedInLabel, email: null));
    });
  });
}
