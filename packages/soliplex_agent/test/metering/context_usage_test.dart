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
      expect(_at(999999).isNearlyFull, isFalse);
    });

    test('is not reached for a nonsensical window', () {
      expect(_at(10, window: 0).isNearlyFull, isFalse);
    });

    test('gives no fraction for a negative window', () {
      expect(_at(10, window: -1).fractionUsed, isNull);
      expect(_at(10, window: -1).isNearlyFull, isFalse);
    });

    test('is 80% below a window of 128000', () {
      expect(_at(102400, window: 127999).isNearlyFull, isTrue);
      expect(_at(102399, window: 127999).isNearlyFull, isFalse);
    });

    test('is 85% at a window of 128000 or more', () {
      expect(_at(108800, window: 128000).isNearlyFull, isTrue);
      expect(_at(108799, window: 128000).isNearlyFull, isFalse);
      expect(_at(170000, window: 200000).isNearlyFull, isTrue);
      expect(_at(169999, window: 200000).isNearlyFull, isFalse);
    });
  });

  group('fractionUsed', () {
    test('does not run past a full window', () {
      // A thread can exceed its window -- the backend counts what it
      // sent, not what fits. The arc has nowhere further to go, and a
      // banner reading over 100% is not a number anyone can act on.
      expect(_at(40000, window: 32768).fractionUsed, 1.0);
    });
  });

  group('isNearlyFull', () {
    test('is false below the threshold of a small window', () {
      expect(_at(26000, window: 32768).isNearlyFull, isFalse);
    });

    test('is true at the threshold of a small window', () {
      // Exactly 80% of the window, so this is the case that says the
      // comparison is inclusive; anything above it passes either way.
      expect(_at(8000, window: 10000).isNearlyFull, isTrue);
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

    test('never fires before the warning does', () {
      // The gauge asks this first, so a critical fraction below the
      // warning would paint the ring red while the banner stayed silent
      // -- the ring and the banner disagreeing, the other way round.
      // A reading between the two is nearly full but not critical.
      for (final window in [32768, 200000]) {
        final between = _at((window * 0.87).round(), window: window);

        expect(between.isNearlyFull, isTrue);
        expect(between.isCritical, isFalse);
      }
    });

    test('is reached at exactly 90% and not a token before', () {
      expect(_at(9000, window: 10000).isCritical, isTrue);
      expect(_at(8999, window: 10000).isCritical, isFalse);
    });

    test('is false with no window to run out of', () {
      expect(const ContextUsage(measuredTokens: 999999).isCritical, isFalse);
    });
  });

  group('draft', () {
    test('is part of the total', () {
      const usage = ContextUsage(
        measuredTokens: 1000,
        estimatedTokens: 200,
        draftTokens: 50,
        contextWindow: 8192,
      );

      expect(usage.tokens, 1250);
      expect(usage.isExact, isFalse);
    });

    test('is the only term withoutDraft drops', () {
      const usage = ContextUsage(
        measuredTokens: 1000,
        estimatedTokens: 200,
        draftTokens: 50,
        contextWindow: 8192,
      );

      final conversation = usage.withoutDraft;

      expect(conversation.measuredTokens, 1000);
      expect(conversation.estimatedTokens, 200);
      expect(conversation.draftTokens, 0);
      expect(conversation.contextWindow, 8192);
    });
  });
}
