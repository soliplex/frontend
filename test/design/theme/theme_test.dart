import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/core/models/color_config.dart';
import 'package:soliplex_frontend/src/design/theme/theme.dart';
import 'package:soliplex_frontend/src/design/theme/theme_extensions.dart';

/// Prevents google_fonts from making real HTTP requests in tests.
class _NoopHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => HttpOverrides.global = _NoopHttpOverrides());
  tearDown(() => HttpOverrides.global = null);

  group('generateColorScheme', () {
    test('maps palette primary to ColorScheme primary', () {
      const palette = ColorPalette.defaultLight();
      final cs = generateColorScheme(
        brightness: Brightness.light,
        palette: palette,
      );

      expect(cs.brightness, Brightness.light);
      expect(cs.primary, palette.primary);
      expect(cs.onPrimary, palette.effectiveOnPrimary);
      expect(cs.secondary, palette.secondary);
      expect(cs.onSecondary, palette.effectiveOnSecondary);
      expect(cs.tertiary, palette.effectiveTertiary);
      expect(cs.onTertiary, palette.effectiveOnTertiary);
      expect(cs.error, palette.effectiveError);
      expect(cs.onError, palette.effectiveOnError);
      expect(cs.surface, palette.background);
      expect(cs.onSurface, palette.foreground);
      expect(cs.onSurfaceVariant, palette.mutedForeground);
      expect(cs.outline, palette.border);
      expect(cs.inverseSurface, palette.foreground);
      expect(cs.onInverseSurface, palette.background);
    });

    test('uses custom palette values', () {
      const palette = ColorPalette(
        primary: Colors.blue,
        secondary: Colors.green,
        background: Colors.white,
        foreground: Colors.black,
        muted: Colors.grey,
        mutedForeground: Colors.blueGrey,
        border: Colors.black12,
        onPrimary: Colors.yellow,
      );
      final cs = generateColorScheme(
        brightness: Brightness.light,
        palette: palette,
      );

      expect(cs.primary, Colors.blue);
      expect(cs.onPrimary, Colors.yellow);
      expect(cs.surface, Colors.white);
      expect(cs.onSurface, Colors.black);
    });

    test('generates dark scheme', () {
      const palette = ColorPalette.defaultDark();
      final cs = generateColorScheme(
        brightness: Brightness.dark,
        palette: palette,
      );

      expect(cs.brightness, Brightness.dark);
      expect(cs.primary, palette.primary);
      expect(cs.surface, palette.background);
    });
  });

  group('soliplexLightTheme', () {
    test('uses default light colors when no colorConfig provided', () {
      final theme = soliplexLightTheme();
      const defaultPalette = ColorPalette.defaultLight();

      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.primary, defaultPalette.primary);
      expect(theme.scaffoldBackgroundColor, defaultPalette.background);
    });

    test('uses custom colors when colorConfig provided', () {
      const customPalette = ColorPalette(
        primary: Colors.blue,
        secondary: Colors.green,
        background: Colors.white,
        foreground: Colors.black,
        muted: Colors.grey,
        mutedForeground: Colors.blueGrey,
        border: Colors.black12,
        onPrimary: Colors.white,
      );
      final config = ColorConfig(light: customPalette);

      final theme = soliplexLightTheme(colorConfig: config);

      expect(theme.colorScheme.primary, Colors.blue);
      expect(theme.colorScheme.onPrimary, Colors.white);
      expect(theme.scaffoldBackgroundColor, Colors.white);
    });

    test('has Material 3 enabled', () {
      final theme = soliplexLightTheme();
      expect(theme.useMaterial3, isTrue);
    });

    test('includes SoliplexTheme extension', () {
      final theme = soliplexLightTheme();
      final ext = theme.extension<SoliplexTheme>();

      expect(ext, isNotNull);
      expect(ext!.colors, theme.colorScheme);
    });

    test('configures component themes', () {
      final theme = soliplexLightTheme();

      expect(theme.dividerTheme.thickness, 1);
    });
  });
}
