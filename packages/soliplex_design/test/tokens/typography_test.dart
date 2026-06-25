import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// Records the families it was asked to resolve and rewrites them so a test
/// can assert the resolver is actually consulted.
class _RecordingResolver implements FontResolver {
  final List<String> requested = [];

  @override
  ResolvedFont resolve(String family, List<String> fallbacks) {
    requested.add(family);
    return ResolvedFont(
      fontFamily: '$family-resolved',
      fontFamilyFallback: fallbacks,
    );
  }
}

void main() {
  group('soliplexTextTheme defaults', () {
    final theme = soliplexTextTheme(lightSoliplexColors);

    test('reproduces the current type scale', () {
      expect(theme.headlineMedium!.fontSize, 28);
      expect(theme.headlineMedium!.fontWeight, FontWeight.w400);
      expect(theme.headlineMedium!.height, 1.3);
      expect(theme.bodyMedium!.fontSize, 16);
      expect(theme.bodyMedium!.fontWeight, FontWeight.w400);
      expect(theme.labelSmall!.fontSize, 12);
      expect(theme.labelSmall!.fontWeight, FontWeight.w500);
    });

    test('colors every role with the foreground', () {
      expect(theme.headlineMedium!.color, lightSoliplexColors.foreground);
      expect(theme.bodyMedium!.color, lightSoliplexColors.foreground);
    });

    test('sets no font family (Material default)', () {
      expect(theme.headlineMedium!.fontFamily, isNull);
      expect(theme.bodyMedium!.fontFamily, isNull);
    });
  });

  group('soliplexTextTheme families', () {
    test('body family applies to body and label roles', () {
      final theme = soliplexTextTheme(lightSoliplexColors, bodyFamily: 'Inter');
      expect(theme.bodyMedium!.fontFamily, 'Inter');
      expect(theme.labelSmall!.fontFamily, 'Inter');
    });

    test('display family applies to headline and title roles', () {
      final theme = soliplexTextTheme(
        lightSoliplexColors,
        bodyFamily: 'Inter',
        displayFamily: 'Fraunces',
      );
      expect(theme.headlineMedium!.fontFamily, 'Fraunces');
      expect(theme.titleLarge!.fontFamily, 'Fraunces');
      expect(theme.bodyMedium!.fontFamily, 'Inter');
    });

    test('display family falls back to body family when null', () {
      final theme = soliplexTextTheme(lightSoliplexColors, bodyFamily: 'Inter');
      expect(theme.headlineMedium!.fontFamily, 'Inter');
    });

    test('passes families and fallbacks through the resolver', () {
      final resolver = _RecordingResolver();
      final theme = soliplexTextTheme(
        lightSoliplexColors,
        bodyFamily: 'Inter',
        fallbacks: const ['Roboto'],
        fontResolver: resolver,
      );
      expect(theme.bodyMedium!.fontFamily, 'Inter-resolved');
      expect(theme.bodyMedium!.fontFamilyFallback, const ['Roboto']);
      expect(resolver.requested, contains('Inter'));
    });
  });

  group('soliplexTextTheme per-role overrides', () {
    test('applies size/weight/height/spacing deltas to one role only', () {
      final theme = soliplexTextTheme(
        lightSoliplexColors,
        bodyLarge: const TypeScaleOverride(
          fontSize: 99,
          fontWeight: FontWeight.w700,
          height: 2,
          letterSpacing: 0.5,
        ),
      );
      expect(theme.bodyLarge!.fontSize, 99);
      expect(theme.bodyLarge!.fontWeight, FontWeight.w700);
      expect(theme.bodyLarge!.height, 2);
      expect(theme.bodyLarge!.letterSpacing, 0.5);
      // A role without an override keeps its default.
      expect(theme.bodyMedium!.fontSize, 16);
    });
  });

  group('soliplexTextTheme builds all 15 roles', () {
    final theme = soliplexTextTheme(lightSoliplexColors);

    test('every Material role is non-null', () {
      expect(theme.displayLarge, isNotNull);
      expect(theme.displayMedium, isNotNull);
      expect(theme.displaySmall, isNotNull);
      expect(theme.headlineLarge, isNotNull);
      expect(theme.headlineMedium, isNotNull);
      expect(theme.headlineSmall, isNotNull);
      expect(theme.titleLarge, isNotNull);
      expect(theme.titleMedium, isNotNull);
      expect(theme.titleSmall, isNotNull);
      expect(theme.bodyLarge, isNotNull);
      expect(theme.bodyMedium, isNotNull);
      expect(theme.bodySmall, isNotNull);
      expect(theme.labelLarge, isNotNull);
      expect(theme.labelMedium, isNotNull);
      expect(theme.labelSmall, isNotNull);
    });

    test('new roles carry soliplex default metrics', () {
      expect(theme.displayLarge!.fontSize, 57);
      expect(theme.displayMedium!.fontSize, 45);
      expect(theme.displaySmall!.fontSize, 36);
      expect(theme.headlineLarge!.fontSize, 32);
      expect(theme.headlineSmall!.fontSize, 24);
      expect(theme.labelLarge!.fontSize, 18);
      expect(theme.labelLarge!.fontWeight, FontWeight.w500);
    });

    test('a per-role override adjusts only the primitives it sets', () {
      final overridden = soliplexTextTheme(
        lightSoliplexColors,
        displayLarge: const TypeScaleOverride(fontSize: 64),
      );
      expect(overridden.displayLarge!.fontSize, 64);
      expect(overridden.displayLarge!.height, 1.2); // default retained
    });
  });
}
