import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/core/models/color_config.dart';

void main() {
  group('ColorPalette', () {
    group('defaultLight', () {
      test('all required fields are populated', () {
        const palette = ColorPalette.defaultLight();
        expect(palette.primary, isNotNull);
        expect(palette.secondary, isNotNull);
        expect(palette.background, isNotNull);
        expect(palette.foreground, isNotNull);
        expect(palette.muted, isNotNull);
        expect(palette.mutedForeground, isNotNull);
        expect(palette.border, isNotNull);
      });

      test('background is light', () {
        const palette = ColorPalette.defaultLight();
        expect(palette.background.computeLuminance(), greaterThan(0.5));
      });

      test('foreground is dark', () {
        const palette = ColorPalette.defaultLight();
        expect(palette.foreground.computeLuminance(), lessThan(0.5));
      });

      test('optional fields are populated with defaults', () {
        const palette = ColorPalette.defaultLight();
        expect(palette.tertiary, isNotNull);
        expect(palette.error, isNotNull);
        expect(palette.onPrimary, isNotNull);
        expect(palette.onSecondary, isNotNull);
        expect(palette.onTertiary, isNotNull);
        expect(palette.onError, isNotNull);
      });
    });

    group('defaultDark', () {
      test('background is dark', () {
        const palette = ColorPalette.defaultDark();
        expect(palette.background.computeLuminance(), lessThan(0.5));
      });

      test('foreground is light', () {
        const palette = ColorPalette.defaultDark();
        expect(palette.foreground.computeLuminance(), greaterThan(0.5));
      });
    });

    group('effective contrast computation', () {
      test('effectiveOnPrimary returns explicit onPrimary when provided', () {
        const palette = ColorPalette(
          primary: Color(0xFF0000FF),
          secondary: Color(0xFF00FF00),
          background: Color(0xFFFFFFFF),
          foreground: Color(0xFF000000),
          muted: Color(0xFFEEEEEE),
          mutedForeground: Color(0xFF666666),
          border: Color(0xFFCCCCCC),
          onPrimary: Color(0xFFFFEEDD),
        );
        expect(palette.effectiveOnPrimary, const Color(0xFFFFEEDD));
      });

      test('effectiveOnPrimary computes white contrast against dark primary',
          () {
        const palette = ColorPalette(
          primary: Color(0xFF000000),
          secondary: Color(0xFF00FF00),
          background: Color(0xFFFFFFFF),
          foreground: Color(0xFF000000),
          muted: Color(0xFFEEEEEE),
          mutedForeground: Color(0xFF666666),
          border: Color(0xFFCCCCCC),
        );
        expect(palette.effectiveOnPrimary, const Color(0xFFFFFFFF));
      });

      test('effectiveOnPrimary computes black contrast against light primary',
          () {
        const palette = ColorPalette(
          primary: Color(0xFFFFFFFF),
          secondary: Color(0xFF00FF00),
          background: Color(0xFFFFFFFF),
          foreground: Color(0xFF000000),
          muted: Color(0xFFEEEEEE),
          mutedForeground: Color(0xFF666666),
          border: Color(0xFFCCCCCC),
        );
        expect(palette.effectiveOnPrimary, const Color(0xFF000000));
      });

      test('effectiveOnSecondary uses contrast computation when null', () {
        const palette = ColorPalette(
          primary: Color(0xFF0000FF),
          secondary: Color(0xFF000000),
          background: Color(0xFFFFFFFF),
          foreground: Color(0xFF000000),
          muted: Color(0xFFEEEEEE),
          mutedForeground: Color(0xFF666666),
          border: Color(0xFFCCCCCC),
        );
        expect(palette.effectiveOnSecondary, const Color(0xFFFFFFFF));
      });

      test('effectiveTertiary returns explicit tertiary when provided', () {
        const palette = ColorPalette(
          primary: Color(0xFF0000FF),
          secondary: Color(0xFF00FF00),
          background: Color(0xFFFFFFFF),
          foreground: Color(0xFF000000),
          muted: Color(0xFFEEEEEE),
          mutedForeground: Color(0xFF666666),
          border: Color(0xFFCCCCCC),
          tertiary: Color(0xFFAA00AA),
        );
        expect(palette.effectiveTertiary, const Color(0xFFAA00AA));
      });

      test('effectiveTertiary returns default neutral when null', () {
        const palette = ColorPalette(
          primary: Color(0xFF0000FF),
          secondary: Color(0xFF00FF00),
          background: Color(0xFFFFFFFF),
          foreground: Color(0xFF000000),
          muted: Color(0xFFEEEEEE),
          mutedForeground: Color(0xFF666666),
          border: Color(0xFFCCCCCC),
        );
        expect(palette.effectiveTertiary, const Color(0xFF7B7486));
      });

      test('effectiveError returns explicit error when provided', () {
        const palette = ColorPalette(
          primary: Color(0xFF0000FF),
          secondary: Color(0xFF00FF00),
          background: Color(0xFFFFFFFF),
          foreground: Color(0xFF000000),
          muted: Color(0xFFEEEEEE),
          mutedForeground: Color(0xFF666666),
          border: Color(0xFFCCCCCC),
          error: Color(0xFFEE0044),
        );
        expect(palette.effectiveError, const Color(0xFFEE0044));
      });

      test('effectiveError returns Material red when null', () {
        const palette = ColorPalette(
          primary: Color(0xFF0000FF),
          secondary: Color(0xFF00FF00),
          background: Color(0xFFFFFFFF),
          foreground: Color(0xFF000000),
          muted: Color(0xFFEEEEEE),
          mutedForeground: Color(0xFF666666),
          border: Color(0xFFCCCCCC),
        );
        expect(palette.effectiveError, const Color(0xFFBA1A1A));
      });
    });

    group('copyWith', () {
      const original = ColorPalette(
        primary: Color(0xFF0000FF),
        secondary: Color(0xFF00FF00),
        background: Color(0xFFFFFFFF),
        foreground: Color(0xFF000000),
        muted: Color(0xFFEEEEEE),
        mutedForeground: Color(0xFF666666),
        border: Color(0xFFCCCCCC),
        tertiary: Color(0xFFAA00AA),
        onPrimary: Color(0xFFFFEEDD),
      );

      test('returns identical palette when no args provided', () {
        final copy = original.copyWith();
        expect(copy, original);
      });

      test('updates primary only', () {
        final copy = original.copyWith(primary: const Color(0xFF111111));
        expect(copy.primary, const Color(0xFF111111));
        expect(copy.secondary, original.secondary);
      });

      test('clearTertiary resets tertiary to null', () {
        final copy = original.copyWith(clearTertiary: true);
        expect(copy.tertiary, isNull);
      });

      test('clearOnPrimary resets onPrimary to null', () {
        final copy = original.copyWith(clearOnPrimary: true);
        expect(copy.onPrimary, isNull);
      });

      test('clear flag takes precedence over new value', () {
        final copy = original.copyWith(
          tertiary: const Color(0xFFFF0000),
          clearTertiary: true,
        );
        expect(copy.tertiary, isNull);
      });
    });

    group('equality', () {
      test('two palettes with same values are equal', () {
        const a = ColorPalette(
          primary: Color(0xFF0000FF),
          secondary: Color(0xFF00FF00),
          background: Color(0xFFFFFFFF),
          foreground: Color(0xFF000000),
          muted: Color(0xFFEEEEEE),
          mutedForeground: Color(0xFF666666),
          border: Color(0xFFCCCCCC),
        );
        const b = ColorPalette(
          primary: Color(0xFF0000FF),
          secondary: Color(0xFF00FF00),
          background: Color(0xFFFFFFFF),
          foreground: Color(0xFF000000),
          muted: Color(0xFFEEEEEE),
          mutedForeground: Color(0xFF666666),
          border: Color(0xFFCCCCCC),
        );
        expect(a, b);
        expect(a.hashCode, b.hashCode);
      });

      test('palettes with different primary are not equal', () {
        const a = ColorPalette(
          primary: Color(0xFF0000FF),
          secondary: Color(0xFF00FF00),
          background: Color(0xFFFFFFFF),
          foreground: Color(0xFF000000),
          muted: Color(0xFFEEEEEE),
          mutedForeground: Color(0xFF666666),
          border: Color(0xFFCCCCCC),
        );
        const b = ColorPalette(
          primary: Color(0xFFFF0000),
          secondary: Color(0xFF00FF00),
          background: Color(0xFFFFFFFF),
          foreground: Color(0xFF000000),
          muted: Color(0xFFEEEEEE),
          mutedForeground: Color(0xFF666666),
          border: Color(0xFFCCCCCC),
        );
        expect(a, isNot(b));
      });
    });
  });

  group('ColorConfig', () {
    test('default constructor uses default light and dark palettes', () {
      const config = ColorConfig();
      expect(config.light, const ColorPalette.defaultLight());
      expect(config.dark, const ColorPalette.defaultDark());
    });

    test('accepts custom light palette only', () {
      const customLight = ColorPalette(
        primary: Color(0xFFAA0000),
        secondary: Color(0xFF00AA00),
        background: Color(0xFFFFFFFF),
        foreground: Color(0xFF000000),
        muted: Color(0xFFEEEEEE),
        mutedForeground: Color(0xFF666666),
        border: Color(0xFFCCCCCC),
      );
      const config = ColorConfig(light: customLight);
      expect(config.light, customLight);
      expect(config.dark, const ColorPalette.defaultDark());
    });

    test('accepts custom dark palette only', () {
      const customDark = ColorPalette(
        primary: Color(0xFFFFAAAA),
        secondary: Color(0xFFAAFFAA),
        background: Color(0xFF000000),
        foreground: Color(0xFFFFFFFF),
        muted: Color(0xFF333333),
        mutedForeground: Color(0xFFAAAAAA),
        border: Color(0xFF555555),
      );
      const config = ColorConfig(dark: customDark);
      expect(config.dark, customDark);
      expect(config.light, const ColorPalette.defaultLight());
    });

    group('copyWith', () {
      test('returns identical config when no args provided', () {
        const config = ColorConfig();
        expect(config.copyWith(), config);
      });

      test('updates light palette only', () {
        const original = ColorConfig();
        const newLight = ColorPalette(
          primary: Color(0xFFAA0000),
          secondary: Color(0xFF00AA00),
          background: Color(0xFFFFFFFF),
          foreground: Color(0xFF000000),
          muted: Color(0xFFEEEEEE),
          mutedForeground: Color(0xFF666666),
          border: Color(0xFFCCCCCC),
        );
        final copy = original.copyWith(light: newLight);
        expect(copy.light, newLight);
        expect(copy.dark, original.dark);
      });
    });

    test('two default configs are equal', () {
      expect(const ColorConfig(), const ColorConfig());
      expect(const ColorConfig().hashCode, const ColorConfig().hashCode);
    });
  });
}
