import 'package:flutter/material.dart';

import '../tokens/breakpoints.dart';
import '../tokens/radii.dart';
import '../tokens/typography.dart';

class SoliplexBadgeThemeData {
  const SoliplexBadgeThemeData({
    required this.background,
    required this.textStyle,
    required this.padding,
  });

  final Color background;
  final TextStyle textStyle;
  final EdgeInsets padding;
}

class SoliplexTheme extends ThemeExtension<SoliplexTheme> {
  const SoliplexTheme({
    required this.colors,
    required this.radii,
    required this.badgeTheme,
    this.codeFont,
  });

  final ColorScheme colors;
  final SoliplexRadii radii;
  final SoliplexBadgeThemeData badgeTheme;

  /// Configured code font family, or `null` for platform-adaptive default.
  final String? codeFont;

  @override
  SoliplexTheme copyWith({
    ColorScheme? colors,
    SoliplexRadii? radii,
    SoliplexBadgeThemeData? badgeTheme,
    String? codeFont,
    bool clearCodeFont = false,
  }) {
    return SoliplexTheme(
      colors: colors ?? this.colors,
      radii: radii ?? this.radii,
      badgeTheme: badgeTheme ?? this.badgeTheme,
      codeFont: clearCodeFont ? null : (codeFont ?? this.codeFont),
    );
  }

  @override
  SoliplexTheme lerp(covariant SoliplexTheme? other, double t) {
    if (other is! SoliplexTheme) return this;
    return SoliplexTheme(
      colors: colors,
      radii: SoliplexRadii.lerp(radii, other.radii, t),
      badgeTheme: badgeTheme,
      codeFont: other.codeFont,
    );
  }

  static SoliplexTheme of(BuildContext context) {
    return Theme.of(context).extension<SoliplexTheme>()!;
  }

  /// Resolves the monospace font family for code display.
  ///
  /// If [codeFont] was configured, returns that directly. Otherwise returns
  /// a platform-adaptive font (SF Mono on Apple, Roboto Mono elsewhere).
  /// Always include the returned value with `fontFamilyFallback: ['monospace']`
  /// for maximum compatibility.
  static String resolveCodeFontFamily(BuildContext context) {
    final theme = Theme.of(context).extension<SoliplexTheme>();
    if (theme?.codeFont != null) return theme!.codeFont!;

    final platform = Theme.of(context).platform;
    final isApple =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    return isApple ? FontFamilies.codeApple : FontFamilies.codeDefault;
  }

  /// Convenience: returns a [TextStyle] configured for monospace/code display.
  ///
  /// Uses [resolveCodeFontFamily] with `['monospace']` fallback.
  static TextStyle codeStyle(BuildContext context) {
    return TextStyle(
      fontFamily: resolveCodeFontFamily(context),
      fontFamilyFallback: const ['monospace'],
    );
  }

  /// Merges the code font family onto an existing [TextStyle].
  ///
  /// If [base] is `null`, returns [codeStyle]. Otherwise copies the code
  /// font family and `['monospace']` fallback onto the base style.
  static TextStyle mergeCode(BuildContext context, [TextStyle? base]) {
    final family = resolveCodeFontFamily(context);
    if (base == null) {
      return TextStyle(
        fontFamily: family,
        fontFamilyFallback: const ['monospace'],
      );
    }
    return base.copyWith(
      fontFamily: family,
      fontFamilyFallback: const ['monospace'],
    );
  }

  /// Returns a responsive AppBar title [TextStyle] based on screen width.
  ///
  /// Uses [headlineSmall] on compact screens (below tablet breakpoint)
  /// and [headlineMedium] on wider screens.
  static TextStyle? appBarTitleStyle(BuildContext context) {
    final theme = Theme.of(context);
    final isCompact =
        MediaQuery.sizeOf(context).width < SoliplexBreakpoints.tablet;
    return isCompact
        ? theme.textTheme.headlineSmall
        : theme.textTheme.headlineMedium;
  }
}
