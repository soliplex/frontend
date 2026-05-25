import 'package:flutter/material.dart';

class SoliplexColors {
  const SoliplexColors({
    required this.background,
    required this.foreground,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.accent,
    required this.onAccent,
    required this.muted,
    required this.mutedForeground,
    required this.destructive,
    required this.onDestructive,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.border,
    required this.outline,
    required this.outlineVariant,
    required this.inputBackground,
    required this.hintText,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.inversePrimary,
    required this.link,
  });

  /// Derives a palette from a single brand [accent] color.
  ///
  /// The accent drives `primary` (and its readable `onPrimary` foreground)
  /// only — that is, buttons and other interactive elements. Every other
  /// slot, including all neutral surfaces and the `primaryContainer` tonal
  /// role used for selected / "this is yours" states, stays from
  /// [lightSoliplexColors] / [darkSoliplexColors]. Container surfaces are
  /// deliberately brand-independent: tinting a surface that itself hosts
  /// colored content distorts how those colors read.
  factory SoliplexColors.fromAccent(
    Color accent, {
    required Brightness brightness,
  }) {
    final base = brightness == Brightness.light
        ? lightSoliplexColors
        : darkSoliplexColors;
    return base.copyWith(
      primary: accent,
      onPrimary: _contrastingForeground(accent),
    );
  }

  final Color background;
  final Color foreground;
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color onSecondary;
  final Color tertiary;
  final Color onTertiary;
  final Color tertiaryContainer;
  final Color onTertiaryContainer;
  final Color accent;
  final Color onAccent;
  final Color muted;
  final Color mutedForeground;
  final Color destructive;
  final Color onDestructive;
  final Color errorContainer;
  final Color onErrorContainer;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color border;
  final Color outline;
  final Color outlineVariant;
  final Color inputBackground;
  final Color hintText;
  final Color surfaceContainerLowest;
  final Color surfaceContainerLow;
  final Color surfaceContainerHigh;
  final Color surfaceContainerHighest;
  final Color inversePrimary;
  final Color link;

  SoliplexColors copyWith({
    Color? background,
    Color? foreground,
    Color? primary,
    Color? onPrimary,
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? secondary,
    Color? onSecondary,
    Color? tertiary,
    Color? onTertiary,
    Color? tertiaryContainer,
    Color? onTertiaryContainer,
    Color? accent,
    Color? onAccent,
    Color? muted,
    Color? mutedForeground,
    Color? destructive,
    Color? onDestructive,
    Color? errorContainer,
    Color? onErrorContainer,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? border,
    Color? outline,
    Color? outlineVariant,
    Color? inputBackground,
    Color? hintText,
    Color? surfaceContainerLowest,
    Color? surfaceContainerLow,
    Color? surfaceContainerHigh,
    Color? surfaceContainerHighest,
    Color? inversePrimary,
    Color? link,
  }) {
    return SoliplexColors(
      background: background ?? this.background,
      foreground: foreground ?? this.foreground,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      onPrimaryContainer: onPrimaryContainer ?? this.onPrimaryContainer,
      secondary: secondary ?? this.secondary,
      onSecondary: onSecondary ?? this.onSecondary,
      tertiary: tertiary ?? this.tertiary,
      onTertiary: onTertiary ?? this.onTertiary,
      tertiaryContainer: tertiaryContainer ?? this.tertiaryContainer,
      onTertiaryContainer: onTertiaryContainer ?? this.onTertiaryContainer,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      muted: muted ?? this.muted,
      mutedForeground: mutedForeground ?? this.mutedForeground,
      destructive: destructive ?? this.destructive,
      onDestructive: onDestructive ?? this.onDestructive,
      errorContainer: errorContainer ?? this.errorContainer,
      onErrorContainer: onErrorContainer ?? this.onErrorContainer,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      border: border ?? this.border,
      outline: outline ?? this.outline,
      outlineVariant: outlineVariant ?? this.outlineVariant,
      inputBackground: inputBackground ?? this.inputBackground,
      hintText: hintText ?? this.hintText,
      surfaceContainerLowest:
          surfaceContainerLowest ?? this.surfaceContainerLowest,
      surfaceContainerLow: surfaceContainerLow ?? this.surfaceContainerLow,
      surfaceContainerHigh: surfaceContainerHigh ?? this.surfaceContainerHigh,
      surfaceContainerHighest:
          surfaceContainerHighest ?? this.surfaceContainerHighest,
      inversePrimary: inversePrimary ?? this.inversePrimary,
      link: link ?? this.link,
    );
  }
}

Color _contrastingForeground(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF0A0A0A);

const lightSoliplexColors = SoliplexColors(
  background: Color(0xffffffff),
  foreground: Color(0xFF0A0A0A),
  primary: Color(0xFF030213),
  onPrimary: Color(0xffffffff),
  primaryContainer: Color(0xFFE0DDDA),
  onPrimaryContainer: Color(0xFF0A0A0A),
  secondary: Color(0xFFF3F3FA),
  onSecondary: Color(0xFF030213),
  tertiary: Color(0xFF6B7280),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFF3F4F6),
  onTertiaryContainer: Color(0xFF374151),
  accent: Color(0xFFE9EBEF),
  onAccent: Color(0xFF030213),
  muted: Color(0xFFECECF0),
  mutedForeground: Color(0xFF595968),
  destructive: Color(0xFFD4183D),
  onDestructive: Color(0xffffffff),
  errorContainer: Color(0xFFFEE2E2),
  onErrorContainer: Color(0xFF991B1B),
  successContainer: Color(0xFFDCFCE7),
  onSuccessContainer: Color(0xFF166534),
  border: Color(0x1A000000),
  outline: Color(0xFFC0C0C4),
  outlineVariant: Color(0xFFE0E0E2),
  inputBackground: Color(0xFFF3F3F5),
  hintText: Color(0xFF666666),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFEFEFEF),
  surfaceContainerHigh: Color(0xFFECECEC),
  surfaceContainerHighest: Color(0xFFE4E4E4),
  inversePrimary: Color(0xFFB0B0B0),
  link: Color(0xFF2563EB),
);

const darkSoliplexColors = SoliplexColors(
  background: Color(0xFF111111),
  foreground: Color(0xFFFAFAFA),
  primary: Color(0xFFFAFAFA),
  onPrimary: Color(0xFF222222),
  primaryContainer: Color(0xFF2A2A2A),
  onPrimaryContainer: Color(0xFFFAFAFA),
  secondary: Color(0xFF2A2A2A),
  onSecondary: Color(0xFFFFFFFF),
  tertiary: Color(0xFF9CA3AF),
  onTertiary: Color(0xFF1F1F1F),
  tertiaryContainer: Color(0xFF2A2A2A),
  onTertiaryContainer: Color(0xFFD1D5DB),
  accent: Color(0xFF2A2A2A),
  onAccent: Color(0xFFFFFFFF),
  muted: Color(0xFF444444),
  mutedForeground: Color(0xFFAAAAAA),
  destructive: Color(0xFFD4183D),
  onDestructive: Color(0xFFFFFFFF),
  errorContainer: Color(0xFF3D1A1A),
  onErrorContainer: Color(0xFFFCA5A5),
  successContainer: Color(0xFF1A3D1A),
  onSuccessContainer: Color(0xFF86EFAC),
  border: Color(0xFF2A2A2A),
  outline: Color(0xFF555555),
  outlineVariant: Color(0xFF3A3A3A),
  inputBackground: Color(0xFF333333),
  hintText: Color(0xFFA3A3A3),
  surfaceContainerLowest: Color(0xFF0E0E0E),
  surfaceContainerLow: Color(0xFF1A1A1A),
  surfaceContainerHigh: Color(0xFF2A2A2A),
  surfaceContainerHighest: Color(0xFF333333),
  inversePrimary: Color(0xFF555555),
  link: Color(0xFF60A5FA),
);
