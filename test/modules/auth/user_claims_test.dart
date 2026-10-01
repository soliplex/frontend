import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/auth/user_claims.dart';

import '../../helpers/test_server_entry.dart';

void main() {
  group('decodeJwtClaims', () {
    test('returns the payload of a well-formed token', () {
      expect(decodeJwtClaims(testJwt({'sub': 'u', 'email': 'a@b'})),
          {'sub': 'u', 'email': 'a@b'});
    });

    test('returns null for a non-JWT string', () {
      expect(decodeJwtClaims('not-a-jwt'), isNull);
      expect(decodeJwtClaims(''), isNull);
    });

    test('returns null for an undecodable payload segment', () {
      expect(decodeJwtClaims('aaa.!!!not-base64!!!.sig'), isNull);
    });

    test('returns null when the payload is not a JSON object', () {
      expect(decodeJwtClaims('aaa.WzFd.sig'), isNull); // payload "[1]"
    });
  });

  group('identityFromClaims', () {
    test('joins iss and sub', () {
      expect(
        identityFromClaims({'iss': 'https://idp.example/realm', 'sub': 'u-1'}),
        'https://idp.example/realm#u-1',
      );
    });

    test('returns null when sub is missing', () {
      expect(identityFromClaims({'iss': 'https://idp.example'}), isNull);
    });

    test('returns null when iss is missing', () {
      expect(identityFromClaims({'sub': 'u-1'}), isNull);
    });

    test('returns null when a claim is blank or not a string', () {
      expect(identityFromClaims({'iss': '', 'sub': 'u-1'}), isNull);
      expect(identityFromClaims({'iss': 'i', 'sub': 7}), isNull);
    });
  });
}
