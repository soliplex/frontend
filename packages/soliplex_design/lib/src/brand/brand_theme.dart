import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:soliplex_design/src/brand/contrast.dart';
import 'package:soliplex_design/src/tokens/colors.dart';

/// The frozen public customization contract.
///
/// Plain Flutter types only (no JSON, no hex strings). Colors flip per
/// [Brightness]; typography and shape are shared across both. A private
/// lowering step (`lowerBrandTheme`) maps this onto the internal token system,
/// which stays free to evolve behind it.
@immutable
class BrandTheme {
  const BrandTheme({
    required this.light,
    required this.dark,
    this.typography = const BrandTypography(),
    this.shape = const BrandShape.rounded(),
  });

  /// The shipped Soliplex look, pinned to today's literals.
  ///
  /// A const constructor so it can be used as a default argument. The palette
  /// values are inlined rather than read from [lightSoliplexColors] /
  /// [darkSoliplexColors] so this public default is both const-constructible
  /// and frozen against internal token refactors.
  const BrandTheme.soliplex()
      : light = _defaultLightColors,
        dark = _defaultDarkColors,
        typography = const BrandTypography(),
        shape = const BrandShape.rounded();

  /// Derives both brightness palettes from a single brand accent.
  factory BrandTheme.fromSeed(
    Color seed, {
    BrandTypography? typography,
    BrandShape? shape,
  }) =>
      BrandTheme(
        light: BrandColorScheme.fromAccent(seed, brightness: Brightness.light),
        dark: BrandColorScheme.fromAccent(seed, brightness: Brightness.dark),
        typography: typography ?? const BrandTypography(),
        shape: shape ?? const BrandShape.rounded(),
      );

  /// Derives each brightness palette from its own accent.
  factory BrandTheme.fromAccents({
    required Color light,
    required Color dark,
    BrandTypography? typography,
    BrandShape? shape,
  }) =>
      BrandTheme(
        light: BrandColorScheme.fromAccent(light, brightness: Brightness.light),
        dark: BrandColorScheme.fromAccent(dark, brightness: Brightness.dark),
        typography: typography ?? const BrandTypography(),
        shape: shape ?? const BrandShape.rounded(),
      );

  final BrandColorScheme light;
  final BrandColorScheme dark;
  final BrandTypography typography;
  final BrandShape shape;

  BrandTheme copyWith({
    BrandColorScheme? light,
    BrandColorScheme? dark,
    BrandTypography? typography,
    BrandShape? shape,
  }) =>
      BrandTheme(
        light: light ?? this.light,
        dark: dark ?? this.dark,
        typography: typography ?? this.typography,
        shape: shape ?? this.shape,
      );

  @override
  bool operator ==(Object other) =>
      other is BrandTheme &&
      other.light == light &&
      other.dark == dark &&
      other.typography == typography &&
      other.shape == shape;

  @override
  int get hashCode => Object.hash(light, dark, typography, shape);
}

/// Seven required semantic roles plus an optional set. Optional roles override
/// the corresponding internal slots during lowering; unset roles fall back to
/// the neutral base, so a fork sets only what it wants to rebrand.
@immutable
class BrandColorScheme {
  const BrandColorScheme({
    required this.primary,
    required this.secondary,
    required this.background,
    required this.foreground,
    required this.muted,
    required this.mutedForeground,
    required this.border,
    this.tertiary,
    this.danger,
    this.success,
    this.warning,
    this.info,
    this.onPrimary,
    this.onSecondary,
    this.onTertiary,
    this.error,
    this.onError,
    this.errorContainer,
    this.onErrorContainer,
    this.successContainer,
    this.onSuccessContainer,
    this.link,
  });

  /// Derives a palette from a single brand [accent].
  ///
  /// The accent drives [primary] and a WCAG-readable [onPrimary]; every other
  /// role stays the neutral base for [brightness], so colored content on those
  /// surfaces keeps reading correctly.
  factory BrandColorScheme.fromAccent(
    Color accent, {
    required Brightness brightness,
  }) {
    final base = brightness == Brightness.light
        ? _defaultLightColors
        : _defaultDarkColors;
    return base.copyWith(
      primary: accent,
      onPrimary: readableOn(accent),
    );
  }

  final Color primary;
  final Color secondary;
  final Color background;
  final Color foreground;
  final Color muted;
  final Color mutedForeground;
  final Color border;

  final Color? tertiary;

  // --- Status *signal* colors ------------------------------------------------
  // Read through `context.danger/success/warning/info`. These tint inline
  // indicators — status text, badges, dots, "this is risky" icons — drawn as
  // foreground on neutral surfaces. They have no fill role and no on-color.
  // For a destructive *action* or an error *surface*, see [error] /
  // [errorContainer]; do not reuse a signal color for those.

  /// Status-signal color for "danger / risk" indicators.
  final Color? danger;

  /// Status-signal color for "success" indicators. The matching soft surface is
  /// [successContainer].
  final Color? success;

  /// Status-signal color for "warning" indicators.
  final Color? warning;

  /// Status-signal color for "info" indicators.
  final Color? info;

  final Color? onPrimary;
  final Color? onSecondary;
  final Color? onTertiary;

  // --- Error / destructive role ----------------------------------------------
  // The Material `ColorScheme.error` family. Distinct from the [danger] signal:
  // these paint solid destructive controls and error *surfaces*, not inline
  // status indicators.

  /// The error / destructive-action role — fills solid destructive buttons and
  /// input error borders (Material `ColorScheme.error`). Pair with [onError]
  /// for legible text on it. Omitted → keeps the base value.
  final Color? error;

  /// Readable foreground for text/icons on [error]. Omitted → auto-derived to a
  /// legible tone when [error] is set, else the base value.
  final Color? onError;

  /// Soft error *surface* — error banners and container fills (Material
  /// `ColorScheme.errorContainer`). Set this together with [error] / [danger]
  /// to keep the error family coherent. Pair with [onErrorContainer].
  final Color? errorContainer;

  /// Readable foreground for content on [errorContainer]. Omitted →
  /// auto-derived when [errorContainer] is set, else the base value.
  final Color? onErrorContainer;

  /// Soft success *surface* — success banners and container fills. The matching
  /// signal color is [success]; set them together. Pair with
  /// [onSuccessContainer].
  final Color? successContainer;

  /// Readable foreground for content on [successContainer]. Omitted →
  /// auto-derived when [successContainer] is set, else the base value.
  final Color? onSuccessContainer;

  /// Hyperlink text color (foreground; it has no on-color). When set, the
  /// lowering layer warns if its contrast against [background] falls below AA —
  /// and only against [background]; links also render on neutral surfaces, so
  /// verify those yourself if they differ much. An unset link keeps the base
  /// value and is not checked.
  final Color? link;

  BrandColorScheme copyWith({
    Color? primary,
    Color? secondary,
    Color? background,
    Color? foreground,
    Color? muted,
    Color? mutedForeground,
    Color? border,
    Color? tertiary,
    Color? danger,
    Color? success,
    Color? warning,
    Color? info,
    Color? onPrimary,
    Color? onSecondary,
    Color? onTertiary,
    Color? error,
    Color? onError,
    Color? errorContainer,
    Color? onErrorContainer,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? link,
  }) =>
      BrandColorScheme(
        primary: primary ?? this.primary,
        secondary: secondary ?? this.secondary,
        background: background ?? this.background,
        foreground: foreground ?? this.foreground,
        muted: muted ?? this.muted,
        mutedForeground: mutedForeground ?? this.mutedForeground,
        border: border ?? this.border,
        tertiary: tertiary ?? this.tertiary,
        danger: danger ?? this.danger,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        info: info ?? this.info,
        onPrimary: onPrimary ?? this.onPrimary,
        onSecondary: onSecondary ?? this.onSecondary,
        onTertiary: onTertiary ?? this.onTertiary,
        error: error ?? this.error,
        onError: onError ?? this.onError,
        errorContainer: errorContainer ?? this.errorContainer,
        onErrorContainer: onErrorContainer ?? this.onErrorContainer,
        successContainer: successContainer ?? this.successContainer,
        onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
        link: link ?? this.link,
      );

  @override
  bool operator ==(Object other) =>
      other is BrandColorScheme &&
      other.primary == primary &&
      other.secondary == secondary &&
      other.background == background &&
      other.foreground == foreground &&
      other.muted == muted &&
      other.mutedForeground == mutedForeground &&
      other.border == border &&
      other.tertiary == tertiary &&
      other.danger == danger &&
      other.success == success &&
      other.warning == warning &&
      other.info == info &&
      other.onPrimary == onPrimary &&
      other.onSecondary == onSecondary &&
      other.onTertiary == onTertiary &&
      other.error == error &&
      other.onError == onError &&
      other.errorContainer == errorContainer &&
      other.onErrorContainer == onErrorContainer &&
      other.successContainer == successContainer &&
      other.onSuccessContainer == onSuccessContainer &&
      other.link == link;

  @override
  int get hashCode => Object.hashAll([
        primary,
        secondary,
        background,
        foreground,
        muted,
        mutedForeground,
        border,
        tertiary,
        danger,
        success,
        warning,
        info,
        onPrimary,
        onSecondary,
        onTertiary,
        error,
        onError,
        errorContainer,
        onErrorContainer,
        successContainer,
        onSuccessContainer,
        link,
      ]);
}

/// Three font families plus optional per-role primitive deltas. Color and
/// per-role family are intentionally absent: color comes from the palette and
/// family is one of the three roles, which avoids dark-mode footguns.
@immutable
class BrandTypography {
  const BrandTypography({
    this.bodyFamily,
    this.displayFamily,
    this.codeFamily,
    this.fallbacks = const [],
    this.headlineMedium,
    this.titleLarge,
    this.titleMedium,
    this.titleSmall,
    this.bodyLarge,
    this.bodyMedium,
    this.bodySmall,
    this.labelMedium,
    this.labelSmall,
  });

  final String? bodyFamily;
  final String? displayFamily;
  final String? codeFamily;
  final List<String> fallbacks;

  final TypeScaleOverride? headlineMedium;
  final TypeScaleOverride? titleLarge;
  final TypeScaleOverride? titleMedium;
  final TypeScaleOverride? titleSmall;
  final TypeScaleOverride? bodyLarge;
  final TypeScaleOverride? bodyMedium;
  final TypeScaleOverride? bodySmall;
  final TypeScaleOverride? labelMedium;
  final TypeScaleOverride? labelSmall;

  BrandTypography copyWith({
    String? bodyFamily,
    String? displayFamily,
    String? codeFamily,
    List<String>? fallbacks,
    TypeScaleOverride? headlineMedium,
    TypeScaleOverride? titleLarge,
    TypeScaleOverride? titleMedium,
    TypeScaleOverride? titleSmall,
    TypeScaleOverride? bodyLarge,
    TypeScaleOverride? bodyMedium,
    TypeScaleOverride? bodySmall,
    TypeScaleOverride? labelMedium,
    TypeScaleOverride? labelSmall,
  }) =>
      BrandTypography(
        bodyFamily: bodyFamily ?? this.bodyFamily,
        displayFamily: displayFamily ?? this.displayFamily,
        codeFamily: codeFamily ?? this.codeFamily,
        fallbacks: fallbacks ?? this.fallbacks,
        headlineMedium: headlineMedium ?? this.headlineMedium,
        titleLarge: titleLarge ?? this.titleLarge,
        titleMedium: titleMedium ?? this.titleMedium,
        titleSmall: titleSmall ?? this.titleSmall,
        bodyLarge: bodyLarge ?? this.bodyLarge,
        bodyMedium: bodyMedium ?? this.bodyMedium,
        bodySmall: bodySmall ?? this.bodySmall,
        labelMedium: labelMedium ?? this.labelMedium,
        labelSmall: labelSmall ?? this.labelSmall,
      );

  @override
  bool operator ==(Object other) =>
      other is BrandTypography &&
      other.bodyFamily == bodyFamily &&
      other.displayFamily == displayFamily &&
      other.codeFamily == codeFamily &&
      listEquals(other.fallbacks, fallbacks) &&
      other.headlineMedium == headlineMedium &&
      other.titleLarge == titleLarge &&
      other.titleMedium == titleMedium &&
      other.titleSmall == titleSmall &&
      other.bodyLarge == bodyLarge &&
      other.bodyMedium == bodyMedium &&
      other.bodySmall == bodySmall &&
      other.labelMedium == labelMedium &&
      other.labelSmall == labelSmall;

  @override
  int get hashCode => Object.hash(
        bodyFamily,
        displayFamily,
        codeFamily,
        Object.hashAll(fallbacks),
        headlineMedium,
        titleLarge,
        titleMedium,
        titleSmall,
        bodyLarge,
        bodyMedium,
        bodySmall,
        labelMedium,
        labelSmall,
      );
}

/// Per-role type-scale deltas applied on top of a base text style.
@immutable
class TypeScaleOverride {
  const TypeScaleOverride({
    this.fontSize,
    this.fontWeight,
    this.height,
    this.letterSpacing,
  });

  final double? fontSize;
  final FontWeight? fontWeight;
  final double? height;
  final double? letterSpacing;

  @override
  bool operator ==(Object other) =>
      other is TypeScaleOverride &&
      other.fontSize == fontSize &&
      other.fontWeight == fontWeight &&
      other.height == height &&
      other.letterSpacing == letterSpacing;

  @override
  int get hashCode => Object.hash(fontSize, fontWeight, height, letterSpacing);
}

/// Corner radii for the four shape steps.
@immutable
class BrandShape {
  const BrandShape.rounded()
      : sm = 6,
        md = 12,
        lg = 16,
        xl = 24;

  const BrandShape.square()
      : sm = 0,
        md = 0,
        lg = 0,
        xl = 0;

  const BrandShape.custom({
    this.sm = 6,
    this.md = 12,
    this.lg = 16,
    this.xl = 24,
  });

  final double sm;
  final double md;
  final double lg;
  final double xl;

  BrandShape copyWith({double? sm, double? md, double? lg, double? xl}) =>
      BrandShape.custom(
        sm: sm ?? this.sm,
        md: md ?? this.md,
        lg: lg ?? this.lg,
        xl: xl ?? this.xl,
      );

  @override
  bool operator ==(Object other) =>
      other is BrandShape &&
      other.sm == sm &&
      other.md == md &&
      other.lg == lg &&
      other.xl == xl;

  @override
  int get hashCode => Object.hash(sm, md, lg, xl);
}

/// The neutral light base, pinned to today's `lightSoliplexColors`. Inlined
/// (not read from the token constants) so [BrandTheme.soliplex] can be a const
/// constructor and the public default stays frozen against token refactors.
const _defaultLightColors = BrandColorScheme(
  primary: Color(0xFF030213),
  secondary: Color(0xFFF3F3FA),
  background: Color(0xFFFFFFFF),
  foreground: Color(0xFF0A0A0A),
  muted: Color(0xFFECECF0),
  mutedForeground: Color(0xFF595968),
  border: Color(0x1A000000),
  tertiary: Color(0xFF6B7280),
  onPrimary: Color(0xFFFFFFFF),
  onSecondary: Color(0xFF030213),
  onTertiary: Color(0xFFFFFFFF),
);

/// The neutral dark base, pinned to today's `darkSoliplexColors`. See
/// [_defaultLightColors] for why the values are inlined.
const _defaultDarkColors = BrandColorScheme(
  primary: Color(0xFFFAFAFA),
  secondary: Color(0xFF2A2A2A),
  background: Color(0xFF111111),
  foreground: Color(0xFFFAFAFA),
  muted: Color(0xFF444444),
  mutedForeground: Color(0xFFAAAAAA),
  border: Color(0xFF2A2A2A),
  tertiary: Color(0xFF9CA3AF),
  onPrimary: Color(0xFF222222),
  onSecondary: Color(0xFFFFFFFF),
  onTertiary: Color(0xFF1F1F1F),
);
