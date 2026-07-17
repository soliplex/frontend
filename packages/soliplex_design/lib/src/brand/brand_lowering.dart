import 'package:flutter/material.dart';

import 'package:soliplex_design/src/brand/brand_theme.dart';
import 'package:soliplex_design/src/brand/contrast.dart';
import 'package:soliplex_design/src/brand/font_resolver.dart';
import 'package:soliplex_design/src/theme/classification_theme.dart';
import 'package:soliplex_design/src/theme/theme.dart';
import 'package:soliplex_design/src/tokens/colors.dart';
import 'package:soliplex_design/src/tokens/radii.dart';
import 'package:soliplex_design/src/tokens/typography.dart';

/// Lowers a public [BrandTheme] onto the internal token system for the given
/// [brightness], producing a ready `ThemeData`.
///
/// The façade roles override a neutral per-brightness base; surfaces and other
/// derived slots stay brand-independent. Unspecified on-colors get a
/// WCAG-readable foreground; an explicitly-set on-color is used as-is, and a
/// pair below WCAG AA is logged as a warning rather than altered — the
/// legibility of a fork's own colors is the fork's call, so there is
/// intentionally no throwing/strict mode. Unspecified status colors fall back
/// to the base. Font families resolve through [fontResolver].
///
/// Contrast warnings go to the `soliplex_design.BrandTheme` logger; attach a
/// LogManager sink before lowering or they are dropped silently.
ThemeData lowerBrandTheme(
  BrandTheme theme,
  Brightness brightness, {
  FontResolver fontResolver = const BundledFontResolver(),
  ClassificationTheme? classifications,
}) {
  final brand = brightness == Brightness.light ? theme.light : theme.dark;
  final colors = _lowerColors(brand, brightness, theme.tint);

  final typography = theme.typography;
  final mono = _lowerMonospace(typography, fontResolver);
  final brandFontTuple = _lowerBrandFont(typography, fontResolver);
  final textTheme = soliplexTextTheme(
    colors,
    bodyFamily: typography.bodyFamily,
    displayFamily: typography.displayFamily,
    brandFont: brandFontTuple,
    fallbacks: typography.fallbacks,
    fontResolver: fontResolver,
    displayLarge: typography.displayLarge,
    displayMedium: typography.displayMedium,
    displaySmall: typography.displaySmall,
    headlineLarge: typography.headlineLarge,
    headlineMedium: typography.headlineMedium,
    headlineSmall: typography.headlineSmall,
    titleLarge: typography.titleLarge,
    titleMedium: typography.titleMedium,
    titleSmall: typography.titleSmall,
    bodyLarge: typography.bodyLarge,
    bodyMedium: typography.bodyMedium,
    bodySmall: typography.bodySmall,
    labelLarge: typography.labelLarge,
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
    monospace: mono,
    brandFont: brandFontTuple,
    textTheme: textTheme,
    classifications: classifications,
  );
}

SoliplexColors _lowerColors(
  BrandColorScheme brand,
  Brightness brightness,
  BrandTint tint,
) {
  final base =
      brightness == Brightness.light ? lightSoliplexColors : darkSoliplexColors;
  final tertiary = brand.tertiary ?? base.tertiary;
  Color derive(Color surface) => readableOn(
        surface,
        tintHue: _tintHue(tint, brand, surface),
        tintStrength: tint.strength,
      );
  Color onColorFor(Color? surface, Color? on, Color baseOn) {
    if (on != null) return on;
    if (surface != null) return derive(surface);
    return baseOn;
  }

  return base.copyWith(
    primary: brand.primary,
    onPrimary: brand.onPrimary ?? derive(brand.primary),
    secondary: brand.secondary,
    onSecondary: brand.onSecondary ?? derive(brand.secondary),
    background: brand.background,
    foreground: brand.foreground,
    muted: brand.muted,
    mutedForeground: brand.mutedForeground,
    border: brand.border,
    tertiary: tertiary,
    onTertiary: onColorFor(brand.tertiary, brand.onTertiary, base.onTertiary),
    danger: brand.danger ?? base.danger,
    success: brand.success ?? base.success,
    warning: brand.warning ?? base.warning,
    info: brand.info ?? base.info,
    destructive: brand.error ?? base.destructive,
    onDestructive: onColorFor(brand.error, brand.onError, base.onDestructive),
    errorContainer: brand.errorContainer ?? base.errorContainer,
    onErrorContainer: onColorFor(
      brand.errorContainer,
      brand.onErrorContainer,
      base.onErrorContainer,
    ),
    successContainer: brand.successContainer ?? base.successContainer,
    onSuccessContainer: onColorFor(
      brand.successContainer,
      brand.onSuccessContainer,
      base.onSuccessContainer,
    ),
    warningContainer: brand.warningContainer ?? base.warningContainer,
    onWarningContainer: onColorFor(
      brand.warningContainer,
      brand.onWarningContainer,
      base.onWarningContainer,
    ),
    infoContainer: brand.infoContainer ?? base.infoContainer,
    onInfoContainer: onColorFor(
      brand.infoContainer,
      brand.onInfoContainer,
      base.onInfoContainer,
    ),
    link: brand.link ?? base.link,
  );
}

/// The hue an auto-derived on-color borrows, per the brand's [tint] policy: the
/// surface it sits on (tonal), the brand's primary, or none.
Color? _tintHue(BrandTint tint, BrandColorScheme brand, Color surface) {
  switch (tint.source) {
    case TintSource.none:
      return null;
    case TintSource.surface:
      return surface;
    case TintSource.primary:
      return brand.primary;
  }
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

({String family, List<String> fallback})? _lowerBrandFont(
  BrandTypography typography,
  FontResolver fontResolver,
) {
  final brand = typography.brandFamily;
  if (brand == null) return null;
  final resolved = fontResolver.resolve(brand, typography.fallbacks);
  return (
    family: resolved.fontFamily ?? brand,
    fallback: resolved.fontFamilyFallback,
  );
}
