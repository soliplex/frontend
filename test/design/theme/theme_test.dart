import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/design/theme/theme.dart';
import 'package:soliplex_frontend/src/design/theme/theme_extensions.dart';
import 'package:soliplex_frontend/src/design/tokens/colors.dart';

void main() {
  group('soliplexLightTheme', () {
    test('uses default light colors when no colors provided', () {
      final theme = soliplexLightTheme();

      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.primary, lightSoliplexColors.primary);
      expect(theme.colorScheme.onPrimary, lightSoliplexColors.onPrimary);
      expect(theme.scaffoldBackgroundColor, lightSoliplexColors.background);
    });

    test('uses custom colors when provided', () {
      const customColors = SoliplexColors(
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

      final theme = soliplexLightTheme(colors: customColors);

      expect(theme.brightness, Brightness.light);
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
      expect(ext!.colors, lightSoliplexColors);
    });

    test('maps ColorScheme fields from SoliplexColors', () {
      final theme = soliplexLightTheme();
      final cs = theme.colorScheme;

      expect(cs.brightness, Brightness.light);
      // Primary
      expect(cs.primary, lightSoliplexColors.primary);
      expect(cs.onPrimary, lightSoliplexColors.onPrimary);
      expect(cs.primaryContainer, lightSoliplexColors.primaryContainer);
      expect(cs.onPrimaryContainer, lightSoliplexColors.onPrimaryContainer);
      // Secondary
      expect(cs.secondary, lightSoliplexColors.secondary);
      expect(cs.onSecondary, lightSoliplexColors.onSecondary);
      expect(cs.secondaryContainer, lightSoliplexColors.muted);
      expect(cs.onSecondaryContainer, lightSoliplexColors.mutedForeground);
      // Tertiary
      expect(cs.tertiary, lightSoliplexColors.tertiary);
      expect(cs.onTertiary, lightSoliplexColors.onTertiary);
      expect(cs.tertiaryContainer, lightSoliplexColors.tertiaryContainer);
      expect(cs.onTertiaryContainer, lightSoliplexColors.onTertiaryContainer);
      // Error
      expect(cs.error, lightSoliplexColors.destructive);
      expect(cs.onError, lightSoliplexColors.onDestructive);
      expect(cs.errorContainer, lightSoliplexColors.errorContainer);
      expect(cs.onErrorContainer, lightSoliplexColors.onErrorContainer);
      // Surface
      expect(cs.surface, lightSoliplexColors.background);
      expect(cs.onSurface, lightSoliplexColors.foreground);
      expect(cs.onSurfaceVariant, lightSoliplexColors.mutedForeground);
      expect(
        cs.surfaceContainerLowest,
        lightSoliplexColors.surfaceContainerLowest,
      );
      expect(cs.surfaceContainerLow, lightSoliplexColors.surfaceContainerLow);
      expect(cs.surfaceContainer, lightSoliplexColors.inputBackground);
      expect(cs.surfaceContainerHigh, lightSoliplexColors.surfaceContainerHigh);
      expect(
        cs.surfaceContainerHighest,
        lightSoliplexColors.surfaceContainerHighest,
      );
      expect(cs.surfaceDim, lightSoliplexColors.accent);
      expect(cs.surfaceBright, lightSoliplexColors.background);
      expect(cs.surfaceTint, lightSoliplexColors.primary);
      // Outline
      expect(cs.outline, lightSoliplexColors.outline);
      expect(cs.outlineVariant, lightSoliplexColors.outlineVariant);
      // Inverse
      expect(cs.inverseSurface, lightSoliplexColors.primary);
      expect(cs.onInverseSurface, lightSoliplexColors.onPrimary);
      expect(cs.inversePrimary, lightSoliplexColors.inversePrimary);
    });

    test('configures component themes', () {
      final theme = soliplexLightTheme();

      expect(theme.appBarTheme.elevation, 0);
      expect(theme.dividerTheme.thickness, 1);
      expect(theme.cardTheme.elevation, 0);
    });
  });
}
