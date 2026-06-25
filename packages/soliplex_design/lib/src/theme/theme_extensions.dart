import 'package:flutter/material.dart';

import 'package:soliplex_design/src/tokens/colors.dart';
import 'package:soliplex_design/src/tokens/radii.dart';

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
    required this.monospace,
    this.brandFont,
  });

  final SoliplexColors colors;
  final SoliplexRadii radii;
  final SoliplexBadgeThemeData badgeTheme;

  /// The code/monospace font family and its fallback chain. Read by
  /// `context.monospace`.
  final ({String family, List<String> fallback}) monospace;

  /// The brand-name font family and fallback chain, or null when no distinct
  /// brand font is configured. Read by `context.brandFont`.
  final ({String family, List<String> fallback})? brandFont;

  @override
  SoliplexTheme copyWith({
    SoliplexColors? colors,
    SoliplexRadii? radii,
    SoliplexBadgeThemeData? badgeTheme,
    ({String family, List<String> fallback})? monospace,
    ({String family, List<String> fallback})? brandFont,
  }) {
    return SoliplexTheme(
      colors: colors ?? this.colors,
      radii: radii ?? this.radii,
      badgeTheme: badgeTheme ?? this.badgeTheme,
      monospace: monospace ?? this.monospace,
      brandFont: brandFont ?? this.brandFont,
    );
  }

  @override
  SoliplexTheme lerp(covariant SoliplexTheme? other, double t) {
    if (other is! SoliplexTheme) return this;
    // Colors, badge styling, and font families are discrete brand tokens, not
    // animatable values — they snap rather than cross-fade. Only the corner
    // radii interpolate.
    return SoliplexTheme(
      colors: colors,
      radii: SoliplexRadii.lerp(radii, other.radii, t),
      badgeTheme: badgeTheme,
      monospace: monospace,
      brandFont: brandFont,
    );
  }

  static SoliplexTheme of(BuildContext context) {
    return Theme.of(context).extension<SoliplexTheme>()!;
  }

  /// The Soliplex theme extension if present, else null — for callers that
  /// must degrade gracefully outside a Soliplex-themed subtree.
  static SoliplexTheme? maybeOf(BuildContext context) {
    return Theme.of(context).extension<SoliplexTheme>();
  }
}

/// The active brand corner radii, falling back to the default scale outside a
/// Soliplex-themed subtree.
extension SoliplexRadiiContext on BuildContext {
  SoliplexRadii get radii =>
      SoliplexTheme.maybeOf(this)?.radii ?? soliplexRadii;
}
