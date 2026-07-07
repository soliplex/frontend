import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/auth/access_token_identity.dart';

// Builds a JWT-shaped string (header.payload.signature) with the given payload.
String _jwt(Map<String, dynamic> payload) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${seg({'alg': 'RS256'})}.${seg(payload)}.sig';
}

void main() {
  test('extracts iss#sub from a well-formed token', () {
    final token = _jwt({'iss': 'https://idp.example/realm', 'sub': 'user-123'});
    expect(accessTokenIdentity(token), 'https://idp.example/realm#user-123');
  });

  test('returns null when sub is missing', () {
    expect(accessTokenIdentity(_jwt({'iss': 'https://idp.example'})), isNull);
  });

  test('returns null when iss is missing', () {
    expect(accessTokenIdentity(_jwt({'sub': 'user-123'})), isNull);
  });

  test('returns null when a claim is blank', () {
    expect(accessTokenIdentity(_jwt({'iss': '', 'sub': 'user-123'})), isNull);
  });

  test('returns null for a non-JWT string', () {
    expect(accessTokenIdentity('not-a-jwt'), isNull);
    expect(accessTokenIdentity(''), isNull);
  });

  test('returns null for an undecodable payload segment', () {
    expect(accessTokenIdentity('aaa.!!!not-base64!!!.sig'), isNull);
  });

  test('tolerates base64url payloads without padding', () {
    expect(accessTokenIdentity(_jwt({'iss': 'i', 'sub': 's'})), 'i#s');
  });
}
