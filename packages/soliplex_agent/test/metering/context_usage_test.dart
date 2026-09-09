import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:test/test.dart';

ContextUsage _at(int tokens, {int? window}) => ContextUsage(
      tokens: tokens,
      contextWindow: window,
      isExact: true,
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

    test('comes earlier for a small window', () {
      // 20% of 32k is a couple more exchanges; the warning has to
      // arrive while there is still room to act on it.
      expect(_at(1, window: 32768).warningThreshold, 0.80);
    });

    test('comes later for a large one', () {
      expect(_at(1, window: 200000).warningThreshold, 0.85);
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

    test('is true once a large window passes its own threshold', () {
      expect(_at((200000 * 0.86).round(), window: 200000).isNearlyFull, isTrue);
    });

    test('stays true when the count exceeds the window', () {
      expect(_at(40000, window: 32768).isNearlyFull, isTrue);
    });
  });
}
