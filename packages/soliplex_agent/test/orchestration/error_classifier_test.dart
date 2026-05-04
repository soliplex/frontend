import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_agent/src/orchestration/error_classifier.dart';
import 'package:test/test.dart';

void main() {
  group('classifyError', () {
    group('SoliplexException hierarchy', () {
      test('AuthException maps to authExpired', () {
        const error = AuthException(message: 'Token expired');
        expect(classifyError(error), equals(FailureReason.authExpired));
      });

      test('NetworkException maps to networkLost', () {
        const error = NetworkException(message: 'No internet');
        expect(classifyError(error), equals(FailureReason.networkLost));
      });
    });

    group('TransportError hierarchy', () {
      test('401 maps to authExpired', () {
        const error = TransportError('Unauthorized', statusCode: 401);
        expect(classifyError(error), equals(FailureReason.authExpired));
      });

      test('403 maps to authExpired', () {
        const error = TransportError('Forbidden', statusCode: 403);
        expect(classifyError(error), equals(FailureReason.authExpired));
      });

      test('429 maps to rateLimited', () {
        const error = TransportError('Too many requests', statusCode: 429);
        expect(classifyError(error), equals(FailureReason.rateLimited));
      });

      test('500 maps to serverError', () {
        const error = TransportError('Internal error', statusCode: 500);
        expect(classifyError(error), equals(FailureReason.serverError));
      });

      test('null statusCode maps to serverError', () {
        const error = TransportError('Connection reset');
        expect(classifyError(error), equals(FailureReason.serverError));
      });
    });

    group('NetworkException unwrap', () {
      test('unwraps to AuthException original cause as authExpired', () {
        const original = AuthException(message: '401');
        const wrapped = NetworkException(
          message: 'Stream resume failed: …',
          originalError: original,
        );
        expect(classifyError(wrapped), equals(FailureReason.authExpired));
      });

      test('falls back to networkLost when originalError is null', () {
        const wrapped = NetworkException(message: 'connection reset');
        expect(classifyError(wrapped), equals(FailureReason.networkLost));
      });
    });

    group('unknown errors', () {
      test('FormatException maps to internalError', () {
        const error = FormatException('bad json');
        expect(classifyError(error), equals(FailureReason.internalError));
      });

      test('StateError maps to internalError', () {
        final error = StateError('unexpected');
        expect(classifyError(error), equals(FailureReason.internalError));
      });

      test('generic Exception maps to internalError', () {
        final error = Exception('something went wrong');
        expect(classifyError(error), equals(FailureReason.internalError));
      });
    });
  });
}
