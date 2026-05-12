import 'package:flutter/material.dart';

import 'colors.dart';

TextTheme soliplexTextTheme(SoliplexColors colors) {
  return TextTheme(
    headlineMedium: TextStyle(
      fontSize: 28,
      fontWeight: .w400,
      height: 1.3,
      color: colors.foreground,
    ),
    titleLarge: TextStyle(
      fontSize: 24,
      fontWeight: .w500,
      height: 1.5,
      color: colors.foreground,
    ),
    titleMedium: TextStyle(
      fontSize: 20,
      fontWeight: .w500,
      height: 1.5,
      color: colors.foreground,
    ),
    titleSmall: TextStyle(
      fontSize: 16,
      fontWeight: .w500,
      height: 1.5,
      color: colors.foreground,
    ),
    bodyLarge: TextStyle(
      fontSize: 18,
      fontWeight: .w400,
      height: 1.5,
      color: colors.foreground,
    ),
    bodyMedium: TextStyle(
      fontSize: 16,
      fontWeight: .w400,
      height: 1.5,
      color: colors.foreground,
    ),
    bodySmall: TextStyle(
      fontSize: 13,
      fontWeight: .w400,
      height: 1.5,
      color: colors.foreground,
    ),
    labelMedium: TextStyle(
      fontSize: 16,
      fontWeight: .w500,
      height: 1.5,
      color: colors.foreground,
    ),
    labelSmall: TextStyle(
      fontSize: 12,
      fontWeight: .w500,
      height: 1.5,
      color: colors.foreground,
    ),
  );
}
