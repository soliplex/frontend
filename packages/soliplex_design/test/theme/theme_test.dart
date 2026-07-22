import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

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
        successContainer: Colors.grey,
        onSuccessContainer: Colors.green,
        warningContainer: Colors.grey,
        onWarningContainer: Colors.orange,
        infoContainer: Colors.grey,
        onInfoContainer: Colors.blue,
        danger: Colors.red,
        success: Colors.green,
        warning: Colors.orange,
        info: Colors.blue,
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

    test('defaults radii to soliplexRadii', () {
      final theme = soliplexLightTheme();

      expect(theme.extension<SoliplexTheme>()!.radii, soliplexRadii);
    });

    test('defaults monospace to the platform family', () {
      final mono = soliplexLightTheme().extension<SoliplexTheme>()!.monospace;

      expect(mono, monospaceFontFamily(defaultTargetPlatform));
    });

    test('threads custom radii into the extension and component shapes', () {
      const customRadii = SoliplexRadii(sm: 1, md: 2, lg: 3, xl: 4);
      final theme = soliplexLightTheme(radii: customRadii);

      expect(theme.extension<SoliplexTheme>()!.radii, customRadii);
      expect(
        (theme.cardTheme.shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(2),
      );
      expect(
        (theme.checkboxTheme.shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(1),
      );
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
      expect(cs.inverseSurface, lightSoliplexColors.foreground);
      expect(cs.onInverseSurface, lightSoliplexColors.background);
      expect(cs.inversePrimary, lightSoliplexColors.inversePrimary);
    });

    test('configures component themes', () {
      final theme = soliplexLightTheme();

      expect(theme.appBarTheme.elevation, 0);
      expect(theme.appBarTheme.centerTitle, isFalse);
      expect(theme.dividerTheme.thickness, 1);
      expect(theme.cardTheme.elevation, 0);
    });

    test('segmented button uses the md radius, not a stadium border', () {
      final theme = soliplexLightTheme();
      final radii = theme.extension<SoliplexTheme>()!.radii;

      final shape =
          theme.segmentedButtonTheme.style?.shape?.resolve(<WidgetState>{});

      expect(shape, isA<RoundedRectangleBorder>());
      expect(
        (shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(radii.md),
      );
    });
  });

  // Regression: component backgrounds were painted with `onPrimary`, whose
  // contrast guarantee holds only against `primary`. The shipped palettes hide
  // it — their `primary` is an inverse neutral, so `onPrimary` lands on a
  // plausible surface tone by coincidence. A brand that keeps a saturated
  // primary in dark mode must set `onPrimary` white for its button labels, and
  // every surface borrowing that slot then rendered white. See issue #418.
  group('surfaces never borrow onPrimary', () {
    // A saturated brand primary in dark mode, with the white onPrimary its own
    // button labels require.
    final colors = darkSoliplexColors.copyWith(
      primary: const Color(0xFF0A7AFF),
      onPrimary: const Color(0xFFFFFFFF),
    );
    final theme = soliplexDarkTheme(colors: colors);

    test('app bar, popup menu and expanded tile take surface roles', () {
      expect(theme.appBarTheme.backgroundColor, colors.background);
      expect(theme.appBarTheme.foregroundColor, colors.foreground);
      expect(theme.popupMenuTheme.color, colors.inputBackground);
      expect(theme.expansionTileTheme.backgroundColor, colors.background);
    });

    test('inverse surface pair stays neutral', () {
      expect(theme.colorScheme.inverseSurface, colors.foreground);
      expect(theme.colorScheme.onInverseSurface, colors.background);
    });

    test('every painted surface still reads as dark', () {
      final surfaces = <String, Color?>{
        'appBar': theme.appBarTheme.backgroundColor,
        'popupMenu': theme.popupMenuTheme.color,
        'expansionTile': theme.expansionTileTheme.backgroundColor,
      };

      for (final MapEntry(key: role, value: color) in surfaces.entries) {
        expect(
          ThemeData.estimateBrightnessForColor(color!),
          Brightness.dark,
          reason: '$role must not render light in dark mode',
        );
      }
    });
  });

  group('soliplexDarkTheme', () {
    test('uses default dark colors when no colors provided', () {
      final theme = soliplexDarkTheme();

      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, darkSoliplexColors.primary);
      expect(theme.scaffoldBackgroundColor, darkSoliplexColors.background);
    });

    test('uses custom colors when provided', () {
      final theme = soliplexDarkTheme(
        colors: darkSoliplexColors.copyWith(primary: Colors.cyan),
      );

      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, Colors.cyan);
    });

    test('includes SoliplexTheme extension with dark colors', () {
      final ext = soliplexDarkTheme().extension<SoliplexTheme>();

      expect(ext, isNotNull);
      expect(ext!.colors, darkSoliplexColors);
    });

    test('has Material 3 enabled', () {
      expect(soliplexDarkTheme().useMaterial3, isTrue);
    });
  });

  group('SoliplexTheme brandFont', () {
    test('copyWith round-trips brandFont', () {
      final base = soliplexLightTheme().extension<SoliplexTheme>()!;
      const font = (family: 'Squada One', fallback: <String>['sans-serif']);
      final updated = base.copyWith(brandFont: font);
      expect(updated.brandFont, equals(font));
      expect(updated.brandFont!.family, 'Squada One');
    });

    test('lerp snaps brandFont to the receiver value', () {
      const font = (family: 'Squada One', fallback: <String>['sans-serif']);
      final a = soliplexLightTheme()
          .extension<SoliplexTheme>()!
          .copyWith(brandFont: font);
      final b = soliplexLightTheme().extension<SoliplexTheme>()!;
      // lerp carries receiver's (a's) brandFont regardless of t.
      expect(a.lerp(b, 0).brandFont, equals(font));
      expect(a.lerp(b, 0.5).brandFont, equals(font));
      expect(a.lerp(b, 1).brandFont, equals(font));
    });

    test('brandFont is null by default', () {
      expect(
        soliplexLightTheme().extension<SoliplexTheme>()!.brandFont,
        isNull,
      );
    });
  });

  group('MarkdownThemeExtension wiring', () {
    test('light theme bakes in a MarkdownThemeExtension', () {
      expect(
        soliplexLightTheme().extension<MarkdownThemeExtension>(),
        isNotNull,
      );
    });

    test('dark theme bakes in a MarkdownThemeExtension', () {
      expect(
        soliplexDarkTheme().extension<MarkdownThemeExtension>(),
        isNotNull,
      );
    });
  });

  group('buildSoliplexThemeData contrast guardrail', () {
    late MemorySink logs;
    setUp(() {
      logs = MemorySink();
      LogManager.instance.addSink(logs);
    });
    tearDown(LogManager.instance.reset);

    test('warns when an explicit on/fill pair is below AA', () {
      // onPrimary == primary => contrast 1.0, far below 4.5.
      final colors = lightSoliplexColors.copyWith(
        primary: const Color(0xFF0A7AFF),
        onPrimary: const Color(0xFF0A7AFF),
      );
      buildSoliplexThemeData(colors: colors, brightness: Brightness.light);
      final warnings =
          logs.records.where((r) => r.level == LogLevel.warning).toList();
      expect(
        warnings.any((r) => r.message.contains('onPrimary')),
        isTrue,
        reason: 'onPrimary/primary below AA should warn',
      );
    });

    test('the shipped palette produces no contrast warnings', () {
      buildSoliplexThemeData(
        colors: lightSoliplexColors,
        brightness: Brightness.light,
      );
      buildSoliplexThemeData(
        colors: darkSoliplexColors,
        brightness: Brightness.dark,
      );
      expect(
        logs.records.where((r) => r.level == LogLevel.warning),
        isEmpty,
      );
    });

    test('warns on a link below AA against the background', () {
      final colors = lightSoliplexColors.copyWith(
        link: lightSoliplexColors.background,
      );
      buildSoliplexThemeData(colors: colors, brightness: Brightness.light);
      expect(
        logs.records.where(
          (r) => r.level == LogLevel.warning && r.message.contains('link'),
        ),
        hasLength(1),
      );
    });
  });
}
