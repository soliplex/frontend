import 'dart:math';

import 'package:soliplex_client/src/http/resume_policy.dart';
import 'package:test/test.dart';

void main() {
  group('ResumePolicy construction', () {
    test('default constructor enables resume with sensible defaults', () {
      const policy = ResumePolicy();
      expect(policy.enabled, isTrue);
      expect(policy.maxAttempts, 5);
    });

    test('noRetry factory disables resume', () {
      const policy = ResumePolicy.noRetry();
      expect(policy.enabled, isFalse);
      expect(policy.maxAttempts, 0);
    });

    test('rejects negative maxAttempts', () {
      expect(
        () => ResumePolicy(maxAttempts: -1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects backoffMultiplier below 1.0 (geometric must grow)', () {
      expect(
        () => ResumePolicy(backoffMultiplier: 0.9),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects jitter outside [0, 1]', () {
      expect(
        () => ResumePolicy(jitter: -0.1),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => ResumePolicy(jitter: 1.5),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('ResumePolicy.backoffFor', () {
    test('attempt=1 returns initialBackoff under zero jitter', () {
      final policy = ResumePolicy(
        initialBackoff: const Duration(milliseconds: 250),
        jitter: 0,
        random: Random(0),
      );
      expect(policy.backoffFor(1), const Duration(milliseconds: 250));
    });

    test('jitter floors the result at 0 (never negative)', () {
      final policy = ResumePolicy(
        initialBackoff: const Duration(milliseconds: 100),
        maxBackoff: const Duration(milliseconds: 200),
        jitter: 1,
        random: _ConstantRandom(0),
      );
      final result = policy.backoffFor(1);
      expect(result.inMicroseconds, greaterThanOrEqualTo(0));
    });

    test('asserts attempt is 1-based', () {
      const policy = ResumePolicy();
      expect(() => policy.backoffFor(0), throwsA(isA<AssertionError>()));
    });
  });

  group('ReconnectStatus invariants', () {
    test('Reconnecting rejects attempt < 1', () {
      expect(
        () => Reconnecting(attempt: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('Reconnected rejects attempt < 1', () {
      expect(
        () => Reconnected(attempt: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('ReconnectFailed rejects attempt < 1', () {
      expect(
        () => ReconnectFailed(attempt: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('error field carries arbitrary Object?, not just String', () {
      final exception = StateError('original');
      final status = Reconnecting(attempt: 1, error: exception);
      expect(status.error, same(exception));
    });
  });
}

class _ConstantRandom implements Random {
  _ConstantRandom(this._value);

  final double _value;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => _value;

  @override
  int nextInt(int max) => 0;
}
