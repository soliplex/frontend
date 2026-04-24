import 'dart:ui';

import 'package:meta/meta.dart';

/// A complete brand color palette for one brightness mode (light or dark).
///
/// Seven required roles define the core visual identity. Six optional roles
/// default to contrast-computed or standard Material values when omitted.
///
/// Example:
/// ```dart
/// const palette = ColorPalette(
///   primary: Color(0xFF1976D2),
///   secondary: Color(0xFF03DAC6),
///   background: Color(0xFFFAFAFA),
///   foreground: Color(0xFF1A1A1E),
///   muted: Color(0xFFE4E4E8),
///   mutedForeground: Color(0xFF6E6E78),
///   border: Color(0xFFC8C8CE),
/// );
/// ```
@immutable
class ColorPalette {
  /// Creates a color palette with 7 required and 6 optional roles.
  const ColorPalette({
    required this.primary,
    required this.secondary,
    required this.background,
    required this.foreground,
    required this.muted,
    required this.mutedForeground,
    required this.border,
    this.tertiary,
    this.error,
    this.onPrimary,
    this.onSecondary,
    this.onTertiary,
    this.onError,
  });

  /// Default light palette — desaturated neutral with grey-purple tones.
  const ColorPalette.defaultLight()
      : primary = const Color(0xFF6B6D7B),
        secondary = const Color(0xFF8E8698),
        background = const Color(0xFFFAFAFA),
        foreground = const Color(0xFF1A1A1E),
        muted = const Color(0xFFE4E4E8),
        mutedForeground = const Color(0xFF6E6E78),
        border = const Color(0xFFC8C8CE),
        tertiary = const Color(0xFF7B7486),
        error = const Color(0xFFBA1A1A),
        onPrimary = const Color(0xFFFFFFFF),
        onSecondary = const Color(0xFFFFFFFF),
        onTertiary = const Color(0xFFFFFFFF),
        onError = const Color(0xFFFFFFFF);

  /// Default dark palette — lightened tones on near-black.
  const ColorPalette.defaultDark()
      : primary = const Color(0xFFB8B9C6),
        secondary = const Color(0xFFCDC5D4),
        background = const Color(0xFF1A1A1D),
        foreground = const Color(0xFFE5E5E8),
        muted = const Color(0xFF2E2E33),
        mutedForeground = const Color(0xFF9A9AA2),
        border = const Color(0xFF48484F),
        tertiary = const Color(0xFFB0A8BA),
        error = const Color(0xFFFFB4AB),
        onPrimary = const Color(0xFF1A1A1E),
        onSecondary = const Color(0xFF1A1A1E),
        onTertiary = const Color(0xFF1A1A1E),
        onError = const Color(0xFF690005);

  // ---- Required roles ----

  /// Brand primary (buttons, links, focus).
  final Color primary;

  /// Secondary brand (FAB, nav indicators).
  final Color secondary;

  /// Main background.
  final Color background;

  /// Main text/icon color.
  final Color foreground;

  /// Subdued backgrounds (app bar, cards, chips).
  final Color muted;

  /// Subdued text (subtitles, hints).
  final Color mutedForeground;

  /// Borders and dividers.
  final Color border;

  // ---- Optional roles (auto-computed when null) ----

  /// Third accent color. Falls back to an explicit neutral per palette.
  final Color? tertiary;

  /// Error states. Falls back to Material red.
  final Color? error;

  /// Text on primary. Falls back to luminance contrast (black/white).
  final Color? onPrimary;

  /// Text on secondary. Falls back to luminance contrast.
  final Color? onSecondary;

  /// Text on tertiary. Falls back to luminance contrast.
  final Color? onTertiary;

  /// Text on error. Falls back to luminance contrast.
  final Color? onError;

  /// Returns [onPrimary] or a contrast color computed from [primary].
  Color get effectiveOnPrimary => onPrimary ?? _contrastColor(primary);

  /// Returns [onSecondary] or a contrast color computed from [secondary].
  Color get effectiveOnSecondary => onSecondary ?? _contrastColor(secondary);

  /// Returns [tertiary] or a default neutral grey.
  Color get effectiveTertiary => tertiary ?? const Color(0xFF7B7486);

  /// Returns [onTertiary] or a contrast color computed from
  /// [effectiveTertiary].
  Color get effectiveOnTertiary =>
      onTertiary ?? _contrastColor(effectiveTertiary);

  /// Returns [error] or a standard Material red.
  Color get effectiveError => error ?? const Color(0xFFBA1A1A);

  /// Returns [onError] or a contrast color computed from [effectiveError].
  Color get effectiveOnError => onError ?? _contrastColor(effectiveError);

  /// Creates a copy with the specified fields replaced.
  ColorPalette copyWith({
    Color? primary,
    Color? secondary,
    Color? background,
    Color? foreground,
    Color? muted,
    Color? mutedForeground,
    Color? border,
    Color? tertiary,
    Color? error,
    Color? onPrimary,
    Color? onSecondary,
    Color? onTertiary,
    Color? onError,
    bool clearTertiary = false,
    bool clearError = false,
    bool clearOnPrimary = false,
    bool clearOnSecondary = false,
    bool clearOnTertiary = false,
    bool clearOnError = false,
  }) {
    return ColorPalette(
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      background: background ?? this.background,
      foreground: foreground ?? this.foreground,
      muted: muted ?? this.muted,
      mutedForeground: mutedForeground ?? this.mutedForeground,
      border: border ?? this.border,
      tertiary: clearTertiary ? null : (tertiary ?? this.tertiary),
      error: clearError ? null : (error ?? this.error),
      onPrimary: clearOnPrimary ? null : (onPrimary ?? this.onPrimary),
      onSecondary: clearOnSecondary ? null : (onSecondary ?? this.onSecondary),
      onTertiary: clearOnTertiary ? null : (onTertiary ?? this.onTertiary),
      onError: clearOnError ? null : (onError ?? this.onError),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorPalette &&
          runtimeType == other.runtimeType &&
          primary == other.primary &&
          secondary == other.secondary &&
          background == other.background &&
          foreground == other.foreground &&
          muted == other.muted &&
          mutedForeground == other.mutedForeground &&
          border == other.border &&
          tertiary == other.tertiary &&
          error == other.error &&
          onPrimary == other.onPrimary &&
          onSecondary == other.onSecondary &&
          onTertiary == other.onTertiary &&
          onError == other.onError;

  @override
  int get hashCode => Object.hash(
        primary,
        secondary,
        background,
        foreground,
        muted,
        mutedForeground,
        border,
        tertiary,
        error,
        onPrimary,
        onSecondary,
        onTertiary,
        onError,
      );

  @override
  String toString() => 'ColorPalette('
      'primary: $primary, '
      'secondary: $secondary, '
      'background: $background, '
      'foreground: $foreground, '
      'muted: $muted, '
      'mutedForeground: $mutedForeground, '
      'border: $border)';
}

/// Returns white or black based on the luminance of the given color.
Color _contrastColor(Color color) {
  return color.computeLuminance() > 0.5
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);
}

/// Color configuration for white-label customization.
///
/// Holds separate [light] and [dark] [ColorPalette] instances that define
/// the complete brand color palette for each brightness mode.
///
/// Example:
/// ```dart
/// const config = ColorConfig(
///   light: ColorPalette(
///     primary: Color(0xFF1976D2),
///     secondary: Color(0xFF03DAC6),
///     background: Color(0xFFFAFAFA),
///     foreground: Color(0xFF1A1A1E),
///     muted: Color(0xFFE4E4E8),
///     mutedForeground: Color(0xFF6E6E78),
///     border: Color(0xFFC8C8CE),
///   ),
/// );
/// ```
@immutable
class ColorConfig {
  /// Creates a color configuration with optional light and dark palettes.
  ///
  /// Both default to their respective [ColorPalette.defaultLight] and
  /// [ColorPalette.defaultDark] constructors.
  const ColorConfig({
    this.light = const ColorPalette.defaultLight(),
    this.dark = const ColorPalette.defaultDark(),
  });

  /// The light mode color palette.
  final ColorPalette light;

  /// The dark mode color palette.
  final ColorPalette dark;

  /// Creates a copy with the specified fields replaced.
  ColorConfig copyWith({
    ColorPalette? light,
    ColorPalette? dark,
  }) {
    return ColorConfig(
      light: light ?? this.light,
      dark: dark ?? this.dark,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorConfig &&
          runtimeType == other.runtimeType &&
          light == other.light &&
          dark == other.dark;

  @override
  int get hashCode => Object.hash(light, dark);

  @override
  String toString() => 'ColorConfig(light: $light, dark: $dark)';
}
