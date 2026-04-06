import 'package:flutter/material.dart';

bool _isCupertino(BuildContext context) {
  final platform = Theme.of(context).platform;
  return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
}

TextStyle appMonospaceTextStyle(BuildContext context) {
  final base = Theme.of(context).textTheme.bodyMedium;

  if (_isCupertino(context)) {
    return base!.copyWith(
      fontFamily: 'SF Mono',
      fontFamilyFallback: const ['Menlo', 'monospace'],
    );
  }

  return base!.copyWith(
    fontFamily: 'Roboto Mono',
    fontFamilyFallback: const ['monospace'],
  );
}

extension TypographyX on BuildContext {
  TextStyle get monospace => appMonospaceTextStyle(this);
}
