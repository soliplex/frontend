import 'package:flutter/material.dart';

import 'package:soliplex_design/src/brand/brand_theme.dart';
import 'package:soliplex_design/src/brand/font_resolver.dart';
import 'package:soliplex_design/src/tokens/colors.dart';

/// Builds all 15 Material text roles with Soliplex-consistent metrics.
///
/// With no arguments beyond [colors] the result is the shipped type scale.
/// [displayFamily] tags the display, headline, and title roles; [bodyFamily]
/// tags the body and label roles (and is the fallback for [displayFamily] when
/// that is null). Family strings resolve through [fontResolver]. A per-role
/// [TypeScaleOverride] adjusts only the primitives it sets, leaving the rest
/// of that role at its default. [TypeScaleOverride.family] redirects a role to
/// one of the three named families; null keeps the role's group default.
/// [brandFont] is a pre-resolved tuple used for [BrandFontRole.brand] routing.
TextTheme soliplexTextTheme(
  SoliplexColors colors, {
  String? bodyFamily,
  String? displayFamily,
  ({String family, List<String> fallback})? brandFont,
  List<String> fallbacks = const [],
  FontResolver fontResolver = const BundledFontResolver(),
  TypeScaleOverride? displayLarge,
  TypeScaleOverride? displayMedium,
  TypeScaleOverride? displaySmall,
  TypeScaleOverride? headlineLarge,
  TypeScaleOverride? headlineMedium,
  TypeScaleOverride? headlineSmall,
  TypeScaleOverride? titleLarge,
  TypeScaleOverride? titleMedium,
  TypeScaleOverride? titleSmall,
  TypeScaleOverride? bodyLarge,
  TypeScaleOverride? bodyMedium,
  TypeScaleOverride? bodySmall,
  TypeScaleOverride? labelLarge,
  TypeScaleOverride? labelMedium,
  TypeScaleOverride? labelSmall,
}) {
  final display = displayFamily ?? bodyFamily;
  final displayFont =
      display == null ? null : fontResolver.resolve(display, fallbacks);
  final bodyFont =
      bodyFamily == null ? null : fontResolver.resolve(bodyFamily, fallbacks);
  final resolvedBrandFont = brandFont == null
      ? null
      : ResolvedFont(
          fontFamily: brandFont.family,
          fontFamilyFallback: brandFont.fallback,
        );

  ResolvedFont? fontFor(ResolvedFont? groupDefault, BrandFontRole? role) {
    return switch (role) {
      null => groupDefault,
      BrandFontRole.body => bodyFont,
      BrandFontRole.display => displayFont,
      BrandFontRole.brand => resolvedBrandFont,
    };
  }

  TextStyle style(
    double fontSize,
    FontWeight fontWeight,
    double height,
    ResolvedFont? groupDefault,
    TypeScaleOverride? override,
  ) {
    final font = fontFor(groupDefault, override?.family);
    return TextStyle(
      fontSize: override?.fontSize ?? fontSize,
      fontWeight: override?.fontWeight ?? fontWeight,
      height: override?.height ?? height,
      letterSpacing: override?.letterSpacing,
      color: colors.foreground,
      fontFamily: font?.fontFamily,
      fontFamilyFallback: font?.fontFamilyFallback,
    );
  }

  return TextTheme(
    displayLarge: style(57, FontWeight.w400, 1.2, displayFont, displayLarge),
    displayMedium: style(45, FontWeight.w400, 1.2, displayFont, displayMedium),
    displaySmall: style(36, FontWeight.w400, 1.2, displayFont, displaySmall),
    headlineLarge: style(32, FontWeight.w400, 1.3, displayFont, headlineLarge),
    headlineMedium:
        style(28, FontWeight.w400, 1.3, displayFont, headlineMedium),
    headlineSmall: style(24, FontWeight.w400, 1.3, displayFont, headlineSmall),
    titleLarge: style(24, FontWeight.w500, 1.5, displayFont, titleLarge),
    titleMedium: style(20, FontWeight.w500, 1.5, displayFont, titleMedium),
    titleSmall: style(16, FontWeight.w500, 1.5, displayFont, titleSmall),
    bodyLarge: style(18, FontWeight.w400, 1.5, bodyFont, bodyLarge),
    bodyMedium: style(16, FontWeight.w400, 1.5, bodyFont, bodyMedium),
    bodySmall: style(13, FontWeight.w400, 1.5, bodyFont, bodySmall),
    // Label scale: 12 (small) / 14 (medium) / 16 (large).
    labelLarge: style(16, FontWeight.w500, 1.5, bodyFont, labelLarge),
    labelMedium: style(14, FontWeight.w500, 1.5, bodyFont, labelMedium),
    labelSmall: style(12, FontWeight.w500, 1.5, bodyFont, labelSmall),
  );
}
