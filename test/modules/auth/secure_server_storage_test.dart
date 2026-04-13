import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/auth/secure_server_storage.dart';
import 'package:soliplex_frontend/src/modules/auth/server_storage.dart';

void main() {
  group('deserializeStorageEntries', () {
    const prefix = 'soliplex_server_';

    String encode(Map<String, dynamic> json) => jsonEncode(json);

    Map<String, dynamic> knownServerJson({
      String serverUrl = 'https://example.com',
      String? alias,
    }) {
      return {
        'serverUrl': serverUrl,
        if (alias != null) 'alias': alias,
        'requiresAuth': true,
      };
    }

    Map<String, dynamic> authenticatedServerJson({
      String serverUrl = 'https://example.com',
    }) {
      return {
        'serverUrl': serverUrl,
        'requiresAuth': true,
        'provider': {
          'discoveryUrl':
              'https://auth.example.com/.well-known/openid-configuration',
          'clientId': 'test-client',
        },
        'tokens': {
          'accessToken': 'access-123',
          'refreshToken': 'refresh-456',
          'expiresAt': '2026-12-31T00:00:00.000Z',
        },
      };
    }

    test('returns empty map for empty input', () {
      final result = deserializeStorageEntries({}, prefix: prefix);
      expect(result, isEmpty);
    });

    test('filters keys not matching prefix', () {
      final raw = {
        'other_key': encode(knownServerJson()),
        'unrelated': 'data',
      };

      final result = deserializeStorageEntries(raw, prefix: prefix);
      expect(result, isEmpty);
    });

    test('extracts serverId by stripping prefix', () {
      final raw = {
        '${prefix}my-server': encode(knownServerJson()),
      };

      final result = deserializeStorageEntries(raw, prefix: prefix);
      expect(result.keys.single, 'my-server');
    });

    test('deserializes KnownServer', () {
      final raw = {
        '${prefix}srv-1': encode(knownServerJson(
          serverUrl: 'https://api.example.com',
        )),
      };

      final result = deserializeStorageEntries(raw, prefix: prefix);
      expect(result['srv-1'], isA<KnownServer>());
      expect(result['srv-1']!.serverUrl, Uri.parse('https://api.example.com'));
    });

    test('deserializes AuthenticatedServer', () {
      final raw = {
        '${prefix}srv-1': encode(authenticatedServerJson()),
      };

      final result = deserializeStorageEntries(raw, prefix: prefix);
      expect(result['srv-1'], isA<AuthenticatedServer>());
    });

    test('silently skips malformed JSON', () {
      final raw = {
        '${prefix}good': encode(knownServerJson()),
        '${prefix}bad': 'not valid json {{{',
      };

      final result = deserializeStorageEntries(raw, prefix: prefix);
      expect(result, hasLength(1));
      expect(result.containsKey('good'), isTrue);
    });

    test('silently skips entries where fromJson throws', () {
      final raw = {
        '${prefix}good': encode(knownServerJson()),
        '${prefix}bad': encode({'missing': 'serverUrl field'}),
      };

      final result = deserializeStorageEntries(raw, prefix: prefix);
      expect(result, hasLength(1));
      expect(result.containsKey('good'), isTrue);
    });

    test('processes multiple valid entries', () {
      final raw = {
        '${prefix}srv-1': encode(knownServerJson(
          serverUrl: 'https://one.example.com',
        )),
        '${prefix}srv-2': encode(knownServerJson(
          serverUrl: 'https://two.example.com',
        )),
      };

      final result = deserializeStorageEntries(raw, prefix: prefix);
      expect(result, hasLength(2));
      expect(result['srv-1']!.serverUrl.host, 'one.example.com');
      expect(result['srv-2']!.serverUrl.host, 'two.example.com');
    });
  });
}
