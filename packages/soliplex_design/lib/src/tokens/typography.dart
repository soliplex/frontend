import 'package:flutter/material.dart';

import 'package:soliplex_design/src/brand/brand_theme.dart';
import 'package:soliplex_design/src/brand/font_resolver.dart';
import 'package:soliplex_design/src/tokens/colors.dart';

/// Builds the Soliplex text theme.
///
/// With no arguments beyond [colors] the result is the shipped type scale.
/// [displayFamily] tags the headline and title roles; [bodyFamily] tags the
/// body and label roles (and is the fallback for [displayFamily] when that is
/// null). Family strings resolve through [fontResolver]. A per-role
/// [TypeScaleOverride] adjusts only the primitives it sets, leaving the rest
/// of that role at its default.
TextTheme soliplexTextTheme(
  SoliplexColors colors, {
  String? bodyFamily,
  String? displayFamily,
  List<String> fallbacks = const [],
  FontResolver fontResolver = const BundledFontResolver(),
  TypeScaleOverride? headlineMedium,
  TypeScaleOverride? titleLarge,
  TypeScaleOverride? titleMedium,
  TypeScaleOverride? titleSmall,
  TypeScaleOverride? bodyLarge,
  TypeScaleOverride? bodyMedium,
  TypeScaleOverride? bodySmall,
  TypeScaleOverride? labelMedium,
  TypeScaleOverride? labelSmall,
}) {
  final display = displayFamily ?? bodyFamily;
  final displayFont =
      display == null ? null : fontResolver.resolve(display, fallbacks);
  final bodyFont =
      bodyFamily == null ? null : fontResolver.resolve(bodyFamily, fallbacks);

  TextStyle style(
    double fontSize,
    FontWeight fontWeight,
    double height,
    ResolvedFont? font,
    TypeScaleOverride? override,
  ) {
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
    headlineMedium:
        style(28, FontWeight.w400, 1.3, displayFont, headlineMedium),
    titleLarge: style(24, FontWeight.w500, 1.5, displayFont, titleLarge),
    titleMedium: style(20, FontWeight.w500, 1.5, displayFont, titleMedium),
    titleSmall: style(16, FontWeight.w500, 1.5, displayFont, titleSmall),
    bodyLarge: style(18, FontWeight.w400, 1.5, bodyFont, bodyLarge),
    bodyMedium: style(16, FontWeight.w400, 1.5, bodyFont, bodyMedium),
    bodySmall: style(13, FontWeight.w400, 1.5, bodyFont, bodySmall),
    labelMedium: style(16, FontWeight.w500, 1.5, bodyFont, labelMedium),
    labelSmall: style(12, FontWeight.w500, 1.5, bodyFont, labelSmall),
  );
}
