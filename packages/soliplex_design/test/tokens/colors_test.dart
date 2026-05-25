import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';

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
        successContainer: Colors.grey,
        onSuccessContainer: Colors.green,
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

    group('fromAccent', () {
      test('light: drives primary only, leaves every other slot untouched', () {
        const accent = Color(0xFF6750A4);
        final derived = SoliplexColors.fromAccent(
          accent,
          brightness: Brightness.light,
        );
        expect(derived.primary, accent);
        // onPrimary picks white because the accent is dark.
        expect(derived.onPrimary, const Color(0xFFFFFFFF));
        // Container surfaces stay brand-independent.
        expect(
          derived.primaryContainer,
          lightSoliplexColors.primaryContainer,
        );
        expect(
          derived.onPrimaryContainer,
          lightSoliplexColors.onPrimaryContainer,
        );
        // Neutral / status / accent slots are inherited verbatim.
        expect(derived.background, lightSoliplexColors.background);
        expect(derived.destructive, lightSoliplexColors.destructive);
        expect(derived.accent, lightSoliplexColors.accent);
      });

      test('light: picks a dark onPrimary for a light accent', () {
        final derived = SoliplexColors.fromAccent(
          const Color(0xFFFFD54F),
          brightness: Brightness.light,
        );
        expect(derived.onPrimary, const Color(0xFF0A0A0A));
      });

      test('dark: drives primary only, leaves every other slot untouched', () {
        const accent = Color(0xFFE91E63);
        final derived = SoliplexColors.fromAccent(
          accent,
          brightness: Brightness.dark,
        );
        expect(derived.primary, accent);
        expect(
          derived.primaryContainer,
          darkSoliplexColors.primaryContainer,
        );
        expect(derived.background, darkSoliplexColors.background);
        expect(derived.accent, darkSoliplexColors.accent);
      });
    });
  });
}
