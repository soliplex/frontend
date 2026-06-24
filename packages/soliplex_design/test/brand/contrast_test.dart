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
    test('picks black on a light background', () {
      expect(readableOn(white), black);
    });

    test('picks white on a dark background', () {
      expect(readableOn(black), const Color(0xFFFFFFFF));
    });

    test('clears AA normal-text contrast on a mid-tone', () {
      expect(
        contrastRatio(readableOn(midGrey), midGrey),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('clears AA even at the worst-case mid luminance', () {
      // Around luminance 0.18, white and black contrast both bottom out. With
      // the softer 0x0A0A0A dark tone this dipped to ≈4.45 (sub-AA); pure black
      // keeps the better choice ≥4.5.
      const worstCase = Color(0xFF777777);
      expect(
        contrastRatio(readableOn(worstCase), worstCase),
        greaterThanOrEqualTo(4.5),
      );
    });
  });
}
