import 'package:flutter/material.dart';

import 'package:soliplex_design/src/brand/brand_theme.dart';
import 'package:soliplex_design/src/brand/contrast.dart';
import 'package:soliplex_design/src/brand/font_resolver.dart';
import 'package:soliplex_design/src/theme/classification_theme.dart';
import 'package:soliplex_design/src/theme/theme.dart';
import 'package:soliplex_design/src/tokens/colors.dart';
import 'package:soliplex_design/src/tokens/radii.dart';
import 'package:soliplex_design/src/tokens/typography.dart';

/// Minimum WCAG AA contrast for normal text. Hand-built on-color pairs below
/// this trip a debug assert; derived on-colors always clear it by
/// construction.
const _minContrast = 4.5;

/// Lowers a public [BrandTheme] onto the internal token system for the given
/// [brightness], producing a ready `ThemeData`.
///
/// The façade roles override a neutral per-brightness base; surfaces and other
/// derived slots stay brand-independent. Unspecified on-colors get a
/// WCAG-readable foreground; unspecified status colors fall back to the base.
/// Font families resolve through [fontResolver].
ThemeData lowerBrandTheme(
  BrandTheme theme,
  Brightness brightness, {
  FontResolver fontResolver = const BundledFontResolver(),
  ClassificationTheme? classifications,
}) {
  final brand = brightness == Brightness.light ? theme.light : theme.dark;
  final colors = _lowerColors(brand, brightness);

  assert(
    _onColorContrastOk(colors),
    'A brand on-color pair is below the $_minContrast:1 WCAG AA threshold.',
  );

  final typography = theme.typography;
  final textTheme = soliplexTextTheme(
    colors,
    bodyFamily: typography.bodyFamily,
    displayFamily: typography.displayFamily,
    fallbacks: typography.fallbacks,
    fontResolver: fontResolver,
    headlineMedium: typography.headlineMedium,
    titleLarge: typography.titleLarge,
    titleMedium: typography.titleMedium,
    titleSmall: typography.titleSmall,
    bodyLarge: typography.bodyLarge,
    bodyMedium: typography.bodyMedium,
    bodySmall: typography.bodySmall,
    labelMedium: typography.labelMedium,
    labelSmall: typography.labelSmall,
  );

  return buildSoliplexThemeData(
    colors: colors,
    brightness: brightness,
    radii: SoliplexRadii(
      sm: theme.shape.sm,
      md: theme.shape.md,
      lg: theme.shape.lg,
      xl: theme.shape.xl,
    ),
    monospace: _lowerMonospace(typography, fontResolver),
    textTheme: textTheme,
    classifications: classifications,
  );
}

SoliplexColors _lowerColors(BrandColorScheme brand, Brightness brightness) {
  final base =
      brightness == Brightness.light ? lightSoliplexColors : darkSoliplexColors;
  final tertiary = brand.tertiary ?? base.tertiary;
  return base.copyWith(
    primary: brand.primary,
    onPrimary: brand.onPrimary ?? readableOn(brand.primary),
    secondary: brand.secondary,
    onSecondary: brand.onSecondary ?? readableOn(brand.secondary),
    background: brand.background,
    foreground: brand.foreground,
    muted: brand.muted,
    mutedForeground: brand.mutedForeground,
    border: brand.border,
    tertiary: tertiary,
    onTertiary: brand.onTertiary ?? readableOn(tertiary),
    danger: brand.danger ?? base.danger,
    success: brand.success ?? base.success,
    warning: brand.warning ?? base.warning,
    info: brand.info ?? base.info,
  );
}

({String family, List<String> fallback})? _lowerMonospace(
  BrandTypography typography,
  FontResolver fontResolver,
) {
  final code = typography.codeFamily;
  if (code == null) return null;
  final resolved = fontResolver.resolve(code, typography.fallbacks);
  return (
    family: resolved.fontFamily ?? code,
    fallback: resolved.fontFamilyFallback,
  );
}

bool _onColorContrastOk(SoliplexColors c) {
  return contrastRatio(c.primary, c.onPrimary) >= _minContrast &&
      contrastRatio(c.secondary, c.onSecondary) >= _minContrast &&
      contrastRatio(c.tertiary, c.onTertiary) >= _minContrast;
}
