import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:test/test.dart';

ContextUsage _at(int tokens, {int? window}) => ContextUsage(
      measuredTokens: tokens,
      contextWindow: window,
    );

void main() {
  group('the warning threshold', () {
    test('is not reached without a window to be a fraction of', () {
      // No denominator, no occupancy, nothing to warn about.
      expect(_at(999999).warningThreshold, isNull);
      expect(_at(999999).isNearlyFull, isFalse);
    });

    test('is not reached for a nonsensical window', () {
      expect(_at(10, window: 0).warningThreshold, isNull);
      expect(_at(10, window: 0).isNearlyFull, isFalse);
    });

    test('treats the boundary as large', () {
      expect(_at(1, window: largeContextWindow).warningThreshold, 0.85);
      expect(_at(1, window: largeContextWindow - 1).warningThreshold, 0.80);
    });
  });

  group('isNearlyFull', () {
    test('is false below the threshold of a small window', () {
      expect(_at(26000, window: 32768).isNearlyFull, isFalse);
    });

    test('is true at the threshold of a small window', () {
      expect(_at(26215, window: 32768).isNearlyFull, isTrue);
    });

    test('holds off longer on a large window', () {
      final fraction82 = (200000 * 0.82).round();

      // Past 80%, which would have warned on a small window, but not
      // yet past 85%.
      expect(_at(fraction82, window: 200000).isNearlyFull, isFalse);
      expect(_at(fraction82, window: 32768).isNearlyFull, isTrue);
    });
  });

  group('isCritical', () {
    test('is false while the thread is merely worth warning about', () {
      // Past the warning threshold of a small window, so the reading is
      // already worth saying something about, but there is room yet.
      final reading = _at(27000, window: 32768);

      expect(reading.isNearlyFull, isTrue);
      expect(reading.isCritical, isFalse);
    });

    test('is true once almost nothing is left', () {
      expect(_at((32768 * 0.91).round(), window: 32768).isCritical, isTrue);
    });

    test('does not hold off on a large window, as the warning does', () {
      // The warning scales with the window because the same fraction is
      // more room; running out does not.
      expect(_at((200000 * 0.91).round(), window: 200000).isCritical, isTrue);
    });

    test('is false with no window to run out of', () {
      expect(const ContextUsage(measuredTokens: 999999).isCritical, isFalse);
    });
  });
}
