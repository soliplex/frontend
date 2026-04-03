import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/auth/connect_flow.dart';

void main() {
  group('describeConnectionError', () {
    group('NetworkException (non-timeout)', () {
      const error = NetworkException(message: 'Could not connect to server.');

      test('shows single URL with scheme', () {
        final result = describeConnectionError(
          error,
          [Uri.parse('https://example.com')],
        );
        expect(result, contains('https://example.com'));
      });

      test('shows all attempted URLs for multi-candidate failure', () {
        final result = describeConnectionError(
          error,
          [
            Uri.parse('https://localhost:8000'),
            Uri.parse('http://localhost:8000'),
          ],
        );
        expect(
          result,
          contains('https://localhost:8000 or http://localhost:8000'),
        );
      });
    });

    group('NetworkException (timeout)', () {
      const error = NetworkException(
        message: 'Connection timed out',
        isTimeout: true,
      );

      test('shows single URL with scheme', () {
        final result = describeConnectionError(
          error,
          [Uri.parse('https://example.com')],
        );
        expect(result, contains('https://example.com'));
      });

      test('shows all attempted URLs for multi-candidate timeout', () {
        final result = describeConnectionError(
          error,
          [
            Uri.parse('https://example.com'),
            Uri.parse('http://example.com'),
          ],
        );
        expect(
          result,
          contains('https://example.com or http://example.com'),
        );
      });
    });

    group('AuthException', () {
      test('shows URL with scheme for 401', () {
        final error = AuthException(statusCode: 401, message: 'Unauthorized');
        final result = describeConnectionError(
          error,
          [Uri.parse('https://example.com')],
        );
        expect(result, contains('https://example.com'));
      });
    });

    group('NotFoundException', () {
      test('shows URL with scheme', () {
        const error = NotFoundException(message: 'Not found');
        final result = describeConnectionError(
          error,
          [Uri.parse('https://example.com')],
        );
        expect(result, contains('https://example.com'));
      });
    });

    group('ApiException', () {
      test('shows URL with scheme for 5xx', () {
        const error = ApiException(statusCode: 500, message: 'Internal error');
        final result = describeConnectionError(
          error,
          [Uri.parse('https://example.com')],
        );
        expect(result, contains('https://example.com'));
      });
    });

    group('fallback (unknown error)', () {
      test('shows URL with scheme', () {
        final error = Exception('something weird');
        final result = describeConnectionError(
          error,
          [Uri.parse('https://example.com')],
        );
        expect(result, contains('https://example.com'));
      });

      test('shows all attempted URLs for multi-candidate', () {
        final error = Exception('something weird');
        final result = describeConnectionError(
          error,
          [
            Uri.parse('https://example.com'),
            Uri.parse('http://example.com'),
          ],
        );
        expect(
          result,
          contains('https://example.com or http://example.com'),
        );
      });
    });

    test('falls back to empty string when no URLs attempted', () {
      const error = NetworkException(message: 'bad');
      final result = describeConnectionError(error, []);
      expect(result, isNotEmpty);
    });
  });
}
