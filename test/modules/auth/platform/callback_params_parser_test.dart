import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/auth/platform/callback_params.dart';
import 'package:soliplex_frontend/src/modules/auth/platform/callback_params_parser.dart';

void main() {
  group('parseCallbackParams', () {
    test('empty params returns NoCallbackParams', () {
      expect(parseCallbackParams({}), isA<NoCallbackParams>());
    });

    test('error param returns WebCallbackError', () {
      final result = parseCallbackParams({
        'error': 'access_denied',
        'error_description': 'User cancelled',
      });

      expect(result, isA<WebCallbackError>());
      final error = result as WebCallbackError;
      expect(error.error, 'access_denied');
      expect(error.errorDescription, 'User cancelled');
    });

    test('error without description sets description to null', () {
      final result = parseCallbackParams({'error': 'server_error'});

      final error = result as WebCallbackError;
      expect(error.error, 'server_error');
      expect(error.errorDescription, isNull);
    });

    test('token param returns WebCallbackSuccess', () {
      final result = parseCallbackParams({'token': 'abc123'});

      expect(result, isA<WebCallbackSuccess>());
      expect((result as WebCallbackSuccess).accessToken, 'abc123');
    });

    test('access_token param used as fallback', () {
      final result = parseCallbackParams({'access_token': 'xyz789'});

      expect(result, isA<WebCallbackSuccess>());
      expect((result as WebCallbackSuccess).accessToken, 'xyz789');
    });

    test('token takes precedence over access_token', () {
      final result = parseCallbackParams({
        'token': 'primary',
        'access_token': 'fallback',
      });

      expect((result as WebCallbackSuccess).accessToken, 'primary');
    });

    test('refresh_token and expires_in forwarded when present', () {
      final result = parseCallbackParams({
        'token': 'abc',
        'refresh_token': 'refresh-xyz',
        'expires_in': '3600',
      });

      final success = result as WebCallbackSuccess;
      expect(success.refreshToken, 'refresh-xyz');
      expect(success.expiresIn, 3600);
    });

    test('invalid expires_in returns null', () {
      final result = parseCallbackParams({
        'token': 'abc',
        'expires_in': 'not-a-number',
      });

      expect((result as WebCallbackSuccess).expiresIn, isNull);
    });

    test('params without error or token returns NoCallbackParams', () {
      final result = parseCallbackParams({'state': 'some-state'});
      expect(result, isA<NoCallbackParams>());
    });
  });

  group('extractQueryParams', () {
    test('parses from search string', () {
      final result = extractQueryParams(
        search: '?code=abc&state=xyz',
        hash: '',
      );

      expect(result, {'code': 'abc', 'state': 'xyz'});
    });

    test('empty search falls back to hash query', () {
      final result = extractQueryParams(
        search: '',
        hash: '#/callback?token=abc&expires_in=3600',
      );

      expect(result, {'token': 'abc', 'expires_in': '3600'});
    });

    test('both empty returns empty map', () {
      final result = extractQueryParams(search: '', hash: '');
      expect(result, isEmpty);
    });

    test('hash without query portion returns empty map', () {
      final result = extractQueryParams(search: '', hash: '#/callback');

      expect(result, isEmpty);
    });

    test('search takes precedence over hash', () {
      final result = extractQueryParams(
        search: '?from=search',
        hash: '#/path?from=hash',
      );

      expect(result['from'], 'search');
    });
  });
}
