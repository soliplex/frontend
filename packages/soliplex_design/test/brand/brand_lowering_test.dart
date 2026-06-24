import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/src/brand/brand_lowering.dart';
import 'package:soliplex_design/src/brand/brand_theme.dart';
import 'package:soliplex_design/src/brand/contrast.dart';
import 'package:soliplex_design/src/brand/font_resolver.dart';
import 'package:soliplex_design/src/theme/theme.dart';
import 'package:soliplex_design/src/theme/theme_extensions.dart';
import 'package:soliplex_design/src/tokens/colors.dart';

class _RecordingResolver implements FontResolver {
  final List<String> requested = [];

  @override
  ResolvedFont resolve(String family, List<String> fallbacks) {
    requested.add(family);
    return ResolvedFont(
      fontFamily: '$family!',
      fontFamilyFallback: fallbacks,
    );
  }
}

void expectSameColors(SoliplexColors a, SoliplexColors b) {
  expect(a.background, b.background, reason: 'background');
  expect(a.foreground, b.foreground, reason: 'foreground');
  expect(a.primary, b.primary, reason: 'primary');
  expect(a.onPrimary, b.onPrimary, reason: 'onPrimary');
  expect(a.primaryContainer, b.primaryContainer, reason: 'primaryContainer');
  expect(
    a.onPrimaryContainer,
    b.onPrimaryContainer,
    reason: 'onPrimaryContainer',
  );
  expect(a.secondary, b.secondary, reason: 'secondary');
  expect(a.onSecondary, b.onSecondary, reason: 'onSecondary');
  expect(a.tertiary, b.tertiary, reason: 'tertiary');
  expect(a.onTertiary, b.onTertiary, reason: 'onTertiary');
  expect(a.tertiaryContainer, b.tertiaryContainer, reason: 'tertiaryContainer');
  expect(
    a.onTertiaryContainer,
    b.onTertiaryContainer,
    reason: 'onTertiaryContainer',
  );
  expect(a.accent, b.accent, reason: 'accent');
  expect(a.onAccent, b.onAccent, reason: 'onAccent');
  expect(a.muted, b.muted, reason: 'muted');
  expect(a.mutedForeground, b.mutedForeground, reason: 'mutedForeground');
  expect(a.destructive, b.destructive, reason: 'destructive');
  expect(a.onDestructive, b.onDestructive, reason: 'onDestructive');
  expect(a.errorContainer, b.errorContainer, reason: 'errorContainer');
  expect(a.onErrorContainer, b.onErrorContainer, reason: 'onErrorContainer');
  expect(a.successContainer, b.successContainer, reason: 'successContainer');
  expect(
    a.onSuccessContainer,
    b.onSuccessContainer,
    reason: 'onSuccessContainer',
  );
  expect(a.danger, b.danger, reason: 'danger');
  expect(a.success, b.success, reason: 'success');
  expect(a.warning, b.warning, reason: 'warning');
  expect(a.info, b.info, reason: 'info');
  expect(a.border, b.border, reason: 'border');
  expect(a.outline, b.outline, reason: 'outline');
  expect(a.outlineVariant, b.outlineVariant, reason: 'outlineVariant');
  expect(a.inputBackground, b.inputBackground, reason: 'inputBackground');
  expect(a.hintText, b.hintText, reason: 'hintText');
  expect(
    a.surfaceContainerLowest,
    b.surfaceContainerLowest,
    reason: 'surfaceContainerLowest',
  );
  expect(
    a.surfaceContainerLow,
    b.surfaceContainerLow,
    reason: 'surfaceContainerLow',
  );
  expect(
    a.surfaceContainerHigh,
    b.surfaceContainerHigh,
    reason: 'surfaceContainerHigh',
  );
  expect(
    a.surfaceContainerHighest,
    b.surfaceContainerHighest,
    reason: 'surfaceContainerHighest',
  );
  expect(a.inversePrimary, b.inversePrimary, reason: 'inversePrimary');
  expect(a.link, b.link, reason: 'link');
}

SoliplexColors loweredColors(BrandTheme theme, Brightness brightness) =>
    lower(theme, brightness).extension<SoliplexTheme>()!.colors;

void main() {
  group('lower defaults are byte-identical to today', () {
    test('light palette', () {
      expectSameColors(
        loweredColors(const BrandTheme.soliplex(), Brightness.light),
        lightSoliplexColors,
      );
    });

    test('dark palette', () {
      expectSameColors(
        loweredColors(const BrandTheme.soliplex(), Brightness.dark),
        darkSoliplexColors,
      );
    });

    test('replicates the integer-alpha badge blend', () {
      final lowered = lower(const BrandTheme.soliplex(), Brightness.light);
      expect(
        lowered.extension<SoliplexTheme>()!.badgeTheme.background,
        soliplexLightTheme().extension<SoliplexTheme>()!.badgeTheme.background,
      );
    });
  });

  group('lower maps the façade onto slots', () {
    test('a seed drives primary with a contrasting onPrimary', () {
      final colors = loweredColors(
        BrandTheme.fromSeed(const Color(0xFF112233)),
        Brightness.light,
      );
      expect(colors.primary, const Color(0xFF112233));
      expect(colors.onPrimary, const Color(0xFFFFFFFF));
    });

    test('an unspecified onColor gets a WCAG-readable foreground', () {
      const handBuilt = BrandColorScheme(
        primary: Color(0xFF808080),
        secondary: Color(0xFF808080),
        background: Color(0xFFFFFFFF),
        foreground: Color(0xFF0A0A0A),
        muted: Color(0xFFECECF0),
        mutedForeground: Color(0xFF595968),
        border: Color(0x1A000000),
      );
      final theme = BrandTheme(
        light: handBuilt,
        dark: const BrandTheme.soliplex().dark,
      );
      final colors = loweredColors(theme, Brightness.light);

      expect(
        contrastRatio(colors.primary, colors.onPrimary),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('unspecified status colors fall back to the neutral base', () {
      final colors = loweredColors(
        BrandTheme.fromSeed(const Color(0xFF112233)),
        Brightness.light,
      );
      expect(colors.danger, lightSoliplexColors.danger);
      expect(colors.info, lightSoliplexColors.info);
    });
  });

  group('lower threads shape and typography', () {
    test('shape drives the radii', () {
      final theme = lower(
        const BrandTheme(
          light: BrandColorScheme(
            primary: Color(0xFF030213),
            secondary: Color(0xFFF3F3FA),
            background: Color(0xFFFFFFFF),
            foreground: Color(0xFF0A0A0A),
            muted: Color(0xFFECECF0),
            mutedForeground: Color(0xFF595968),
            border: Color(0x1A000000),
            onPrimary: Color(0xFFFFFFFF),
            onSecondary: Color(0xFF030213),
          ),
          dark: BrandColorScheme(
            primary: Color(0xFFFAFAFA),
            secondary: Color(0xFF2A2A2A),
            background: Color(0xFF111111),
            foreground: Color(0xFFFAFAFA),
            muted: Color(0xFF444444),
            mutedForeground: Color(0xFFAAAAAA),
            border: Color(0xFF2A2A2A),
            onPrimary: Color(0xFF222222),
            onSecondary: Color(0xFFFFFFFF),
          ),
          shape: BrandShape.square(),
        ),
        Brightness.light,
      );
      expect(theme.extension<SoliplexTheme>()!.radii.md, 0);
      expect(
        (theme.cardTheme.shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(0),
      );
    });

    test('body and display families flow into the text theme', () {
      final theme = lower(
        BrandTheme.fromSeed(
          const Color(0xFF112233),
          typography: const BrandTypography(bodyFamily: 'Inter'),
        ),
        Brightness.light,
      );
      expect(theme.textTheme.bodyMedium!.fontFamily, 'Inter');
      // Display falls back to the body family.
      expect(theme.textTheme.headlineMedium!.fontFamily, 'Inter');
    });

    test('codeFamily becomes the monospace token', () {
      final theme = lower(
        BrandTheme.fromSeed(
          const Color(0xFF112233),
          typography: const BrandTypography(codeFamily: 'Brandospace'),
        ),
        Brightness.light,
      );
      expect(
        theme.extension<SoliplexTheme>()!.monospace.family,
        'Brandospace',
      );
    });

    test('families resolve through the injected FontResolver', () {
      final resolver = _RecordingResolver();
      final theme = lower(
        BrandTheme.fromSeed(
          const Color(0xFF112233),
          typography: const BrandTypography(bodyFamily: 'Inter'),
        ),
        Brightness.light,
        fontResolver: resolver,
      );
      expect(theme.textTheme.bodyMedium!.fontFamily, 'Inter!');
      expect(resolver.requested, contains('Inter'));
    });
  });

  group('lower contrast assert', () {
    test('fires in debug on a sub-threshold on-color pair', () {
      final bad = const BrandTheme.soliplex().light.copyWith(
            primary: const Color(0xFFFFFFFF),
            onPrimary: const Color(0xFFFFFFFF),
          );
      expect(
        () => lower(
          BrandTheme(light: bad, dark: const BrandTheme.soliplex().dark),
          Brightness.light,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
