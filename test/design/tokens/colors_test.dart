import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/design/tokens/colors.dart';

void main() {
  group('SoliplexColors', () {
    test('lightSoliplexColors has expected primary', () {
      expect(lightSoliplexColors.primary, const Color(0xFF030213));
    });

    test('darkSoliplexColors has expected primary', () {
      expect(darkSoliplexColors.primary, const Color(0xFFFAFAFA));
    });

    test('all light color roles are non-null via constructor', () {
      const colors = SoliplexColors(
        background: Colors.white,
        foreground: Colors.black,
        primary: Colors.blue,
        onPrimary: Colors.white,
        primaryContainer: Colors.grey,
        onPrimaryContainer: Colors.black,
        secondary: Colors.grey,
        onSecondary: Colors.black,
        tertiary: Colors.grey,
        onTertiary: Colors.white,
        tertiaryContainer: Colors.grey,
        onTertiaryContainer: Colors.black,
        accent: Colors.orange,
        onAccent: Colors.white,
        muted: Colors.grey,
        mutedForeground: Colors.grey,
        destructive: Colors.red,
        onDestructive: Colors.white,
        errorContainer: Colors.grey,
        onErrorContainer: Colors.red,
        border: Colors.grey,
        outline: Colors.grey,
        outlineVariant: Colors.grey,
        inputBackground: Colors.grey,
        hintText: Colors.grey,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: Colors.grey,
        surfaceContainerHigh: Colors.grey,
        surfaceContainerHighest: Colors.grey,
        inversePrimary: Colors.grey,
        link: Colors.blue,
      );
      expect(colors.background, Colors.white);
      expect(colors.foreground, Colors.black);
      expect(colors.primary, Colors.blue);
    });
  });
}
