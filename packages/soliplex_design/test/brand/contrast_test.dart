import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/src/brand/contrast.dart';

void main() {
  const white = Color(0xFFFFFFFF);
  const black = Color(0xFF000000);
  const midGrey = Color(0xFF808080);

  group('contrastRatio', () {
    test('white on black is the 21:1 maximum', () {
      expect(contrastRatio(white, black), closeTo(21, 0.01));
    });

    test('a color against itself is 1:1', () {
      expect(contrastRatio(midGrey, midGrey), closeTo(1, 0.001));
    });

    test('is symmetric', () {
      expect(contrastRatio(white, midGrey), contrastRatio(midGrey, white));
    });
  });

  group('readableOn', () {
    const nearBlack = Color(0xFF212427);
    const nearWhite = Color(0xFFFAFAFA);

    test('prefers the soft near-black on a light background', () {
      expect(readableOn(white), nearBlack);
    });

    test('prefers the soft near-white on a dark background', () {
      expect(readableOn(black), nearWhite);
    });

    test('escalates to darker tones only as the surface forces it', () {
      // The near-black clears AA on light surfaces; as the surface darkens
      // toward the crossover it steps down through the cascade, reaching pure
      // black only in the last sliver above the crossover.
      expect(readableOn(const Color(0xFFB0B0B0)), nearBlack);
      expect(readableOn(const Color(0xFF858585)), const Color(0xFF0A0A0A));
      expect(readableOn(const Color(0xFF767676)), black);
    });

    test('never bottoms out below AA across the mid-tone range', () {
      for (var v = 0; v <= 255; v++) {
        final surface = Color.fromARGB(255, v, v, v);
        expect(
          contrastRatio(readableOn(surface), surface),
          greaterThanOrEqualTo(4.5),
          reason: 'grey #${v.toRadixString(16)}',
        );
      }
    });

    group('tint', () {
      test('nudges the near-tone toward a chromatic hue, lightness kept', () {
        const blue = Color(0xFF2266CC);
        final tinted = readableOn(white, tintHue: blue, tintStrength: 0.08);
        expect(tinted, isNot(nearBlack));
        // Bluer than the neutral near-black, but still dark and AA-legible.
        expect(tinted.b, greaterThan(tinted.r));
        expect(
          contrastRatio(tinted, white),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('adds no tint for an achromatic hue source', () {
        expect(
          readableOn(white, tintHue: const Color(0xFF808080), tintStrength: .2),
          nearBlack,
        );
      });

      test('adds no tint at zero strength', () {
        expect(
          readableOn(white, tintHue: const Color(0xFF2266CC)),
          nearBlack,
        );
      });

      test('drops the tint when it would fall below AA, keeping the tone', () {
        // On a mid-light surface a warm tint nudges the near-black just below
        // 4.5:1, so the cascade falls through to the untinted near-black.
        const surface = Color(0xFF8A8A8A);
        final tone = readableOn(
          surface,
          tintHue: const Color(0xFFFF8800),
          tintStrength: 0.12,
        );
        expect(tone, nearBlack); // untinted, not the warm-tinted tone
        expect(contrastRatio(tone, surface), greaterThanOrEqualTo(4.5));
      });
    });
  });
}
