import 'package:soliplex_client/src/http/resume_policy.dart';
import 'package:test/test.dart';

import '_constant_random.dart';

void main() {
  group('ResumePolicy construction', () {
    test('default constructor enables resume', () {
      const policy = ResumePolicy();
      expect(policy.enabled, isTrue);
      expect(policy.maxAttempts, greaterThan(0));
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
        random: ConstantRandom(0),
      );
      expect(policy.backoffFor(1), const Duration(milliseconds: 250));
    });

    test('worst-case negative jitter clamps at zero, not below', () {
      // jitterFactor = 1 + (0*2 - 1) * 1.0 = 0 → 100 ms * 0 = 0 ms.
      // Pins that the post-jitter clamp lower bound is exactly zero,
      // not "any non-negative value".
      final policy = ResumePolicy(
        initialBackoff: const Duration(milliseconds: 100),
        maxBackoff: const Duration(milliseconds: 200),
        jitter: 1,
        random: ConstantRandom(0),
      );
      expect(policy.backoffFor(1), Duration.zero);
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
