import 'package:flutter/material.dart';

import '../../shared/platform_resolver.dart';

TextStyle appMonospaceTextStyle(BuildContext context, {TextStyle? base}) {
  final effectiveBase = base ?? Theme.of(context).textTheme.bodyMedium;

  if (isCupertino(context)) {
    return effectiveBase!.copyWith(
      fontFamily: 'SF Mono',
      fontFamilyFallback: const ['Menlo', 'monospace'],
    );
  }

  return effectiveBase!.copyWith(
    fontFamily: 'Roboto Mono',
    fontFamilyFallback: const ['monospace'],
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
}
