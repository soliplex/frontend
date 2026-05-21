import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:test/test.dart';

void main() {
  group('FailureReason', () {
    test('has exactly 9 values', () {
      expect(FailureReason.values, hasLength(9));
    });

    test('contains all expected values', () {
      expect(
        FailureReason.values,
        containsAll([
          FailureReason.serverError,
          FailureReason.authExpired,
          FailureReason.permissionDenied,
          FailureReason.networkLost,
          FailureReason.streamResumeFailed,
          FailureReason.rateLimited,
          FailureReason.toolExecutionFailed,
          FailureReason.internalError,
          FailureReason.cancelled,
        ]),
      );
    });

    test('each value has a distinct name', () {
      final names = FailureReason.values.map((v) => v.name).toSet();
      expect(names, hasLength(FailureReason.values.length));
    });
  });
}
