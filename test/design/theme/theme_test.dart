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
      expect(theme.colorScheme.primary, kLightSoliplexColors.primary);
      expect(theme.colorScheme.onPrimary, kLightSoliplexColors.onPrimary);
      expect(theme.scaffoldBackgroundColor, kLightSoliplexColors.background);
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
      expect(ext!.colors, kLightSoliplexColors);
    });

    test('maps ColorScheme fields from SoliplexColors', () {
      final theme = soliplexLightTheme();
      final cs = theme.colorScheme;

      expect(cs.brightness, Brightness.light);
      // Primary
      expect(cs.primary, kLightSoliplexColors.primary);
      expect(cs.onPrimary, kLightSoliplexColors.onPrimary);
      expect(cs.primaryContainer, kLightSoliplexColors.primaryContainer);
      expect(cs.onPrimaryContainer, kLightSoliplexColors.onPrimaryContainer);
      // Secondary
      expect(cs.secondary, kLightSoliplexColors.secondary);
      expect(cs.onSecondary, kLightSoliplexColors.onSecondary);
      expect(cs.secondaryContainer, kLightSoliplexColors.muted);
      expect(cs.onSecondaryContainer, kLightSoliplexColors.mutedForeground);
      // Tertiary
      expect(cs.tertiary, kLightSoliplexColors.tertiary);
      expect(cs.onTertiary, kLightSoliplexColors.onTertiary);
      expect(cs.tertiaryContainer, kLightSoliplexColors.tertiaryContainer);
      expect(cs.onTertiaryContainer, kLightSoliplexColors.onTertiaryContainer);
      // Error
      expect(cs.error, kLightSoliplexColors.destructive);
      expect(cs.onError, kLightSoliplexColors.onDestructive);
      expect(cs.errorContainer, kLightSoliplexColors.errorContainer);
      expect(cs.onErrorContainer, kLightSoliplexColors.onErrorContainer);
      // Surface
      expect(cs.surface, kLightSoliplexColors.background);
      expect(cs.onSurface, kLightSoliplexColors.foreground);
      expect(cs.onSurfaceVariant, kLightSoliplexColors.mutedForeground);
      expect(
        cs.surfaceContainerLowest,
        kLightSoliplexColors.surfaceContainerLowest,
      );
      expect(cs.surfaceContainerLow, kLightSoliplexColors.surfaceContainerLow);
      expect(cs.surfaceContainer, kLightSoliplexColors.inputBackground);
      expect(
        cs.surfaceContainerHigh,
        kLightSoliplexColors.surfaceContainerHigh,
      );
      expect(
        cs.surfaceContainerHighest,
        kLightSoliplexColors.surfaceContainerHighest,
      );
      expect(cs.surfaceDim, kLightSoliplexColors.accent);
      expect(cs.surfaceBright, kLightSoliplexColors.background);
      expect(cs.surfaceTint, kLightSoliplexColors.primary);
      // Outline
      expect(cs.outline, kLightSoliplexColors.outline);
      expect(cs.outlineVariant, kLightSoliplexColors.outlineVariant);
      // Inverse
      expect(cs.inverseSurface, kLightSoliplexColors.primary);
      expect(cs.onInverseSurface, kLightSoliplexColors.onPrimary);
      expect(cs.inversePrimary, kLightSoliplexColors.inversePrimary);
    });

    test('configures component themes', () {
      final theme = soliplexLightTheme();

      expect(theme.appBarTheme.elevation, 0);
      expect(theme.dividerTheme.thickness, 1);
      expect(theme.cardTheme.elevation, 0);
    });
  });
}
