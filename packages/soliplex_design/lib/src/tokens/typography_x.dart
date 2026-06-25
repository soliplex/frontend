import 'package:flutter/material.dart';

import 'package:soliplex_design/src/theme/theme_extensions.dart';

/// The monospace font family and fallbacks to use on [platform].
({String family, List<String> fallback}) monospaceFontFamily(
  TargetPlatform platform,
) {
  final isCupertino =
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  return isCupertino
      ? (family: 'SF Mono', fallback: const ['Menlo', 'monospace'])
      : (family: 'Roboto Mono', fallback: const ['monospace']);
}

TextStyle? brandNameTextStyle(BuildContext context, TextStyle? base) {
  final brand = SoliplexTheme.maybeOf(context)?.brandFont;
  if (brand == null) return base;
  return base?.copyWith(
    fontFamily: brand.family,
    fontFamilyFallback: brand.fallback,
  );
}

TextStyle appMonospaceTextStyle(BuildContext context, {TextStyle? base}) {
  final effectiveBase = base ?? Theme.of(context).textTheme.bodyMedium;
  final mono = SoliplexTheme.maybeOf(context)?.monospace ??
      monospaceFontFamily(Theme.of(context).platform);
  return effectiveBase!.copyWith(
    fontFamily: mono.family,
    fontFamilyFallback: mono.fallback,
  );
}

extension TypographyX on BuildContext {
  /// Monospace using `bodyMedium` (16pt) as the base.
  TextStyle get monospace => appMonospaceTextStyle(this);

  /// Monospace built on top of a specific text theme entry, e.g.
  /// `context.monospaceOn(Theme.of(context).textTheme.labelSmall)` for a
  /// 12pt monospace badge.
  TextStyle monospaceOn(TextStyle? base) =>
      appMonospaceTextStyle(this, base: base);

  /// The brand-name font family + fallback, or null when no distinct brand
  /// font is configured.
  ({String family, List<String> fallback})? get brandFont =>
      SoliplexTheme.maybeOf(this)?.brandFont;

  /// [base] with the brand-name font applied, or [base] unchanged when no
  /// brand font is configured.
  TextStyle? brandNameOn(TextStyle? base) => brandNameTextStyle(this, base);
}
