import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';

void main() {
  group('hashedHueColor', () {
    test('is deterministic for the same seed', () {
      expect(
        hashedHueColor('Manuals', Brightness.light),
        equals(hashedHueColor('Manuals', Brightness.light)),
      );
    });

    test('separates different seeds', () {
      final colors = <Color>{
        for (final seed in ['Manuals', 'Urgent', 'Archived', 'Chinook'])
          hashedHueColor(seed, Brightness.light),
      };

      expect(colors.length, equals(4));
    });

    test('varies the tone with brightness', () {
      // Same hue, different lightness, so whatever is drawn on top stays
      // legible in either theme.
      expect(
        hashedHueColor('Manuals', Brightness.light),
        isNot(hashedHueColor('Manuals', Brightness.dark)),
      );
    });

    test('handles an empty seed', () {
      expect(hashedHueColor('', Brightness.light), isA<Color>());
    });
  });

  group('colorFromHex', () {
    test('parses a full six-digit swatch', () {
      expect(colorFromHex('#42D76D'), equals(const Color(0xFF42D76D)));
    });

    test('accepts lower case and a missing hash', () {
      expect(colorFromHex('42d76d'), equals(const Color(0xFF42D76D)));
    });

    test('expands three-digit shorthand', () {
      expect(colorFromHex('#4D7'), equals(const Color(0xFF44DD77)));
    });

    test('trims surrounding whitespace', () {
      expect(colorFromHex('  #42D76D '), equals(const Color(0xFF42D76D)));
    });

    test('returns null for anything it cannot read', () {
      // Null rather than a substituted default: the caller falls back to
      // something that suits its own surface, and a silent black would
      // look like a deliberate choice.
      for (final bad in ['', '#', 'nope', '#12345', '#1234567', '#GGGGGG']) {
        expect(colorFromHex(bad), isNull, reason: '"$bad" should not parse');
      }
    });
  });

  group('hueColor', () {
    test('wraps past a full turn', () {
      // A caller handing over a server-derived hue must not have to
      // normalise it first.
      expect(
        hueColor(370, Brightness.light),
        equals(hueColor(10, Brightness.light)),
      );
    });

    test('is what hashedHueColor is built from', () {
      // The two must not drift: hashing only chooses the hue.
      expect(
        hashedHueColor('Manuals', Brightness.dark),
        equals(
          hueColor(
            HSLColor.fromColor(
              hashedHueColor('Manuals', Brightness.dark),
            ).hue,
            Brightness.dark,
          ),
        ),
      );
    });
  });
}
