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
  });

  final SoliplexColors colors;
  final SoliplexRadii radii;
  final SoliplexBadgeThemeData badgeTheme;

  /// The code/monospace font family and its fallback chain. Read by
  /// `context.monospace`.
  final ({String family, List<String> fallback}) monospace;

  @override
  SoliplexTheme copyWith({
    SoliplexColors? colors,
    SoliplexRadii? radii,
    SoliplexBadgeThemeData? badgeTheme,
    ({String family, List<String> fallback})? monospace,
  }) {
    return SoliplexTheme(
      colors: colors ?? this.colors,
      radii: radii ?? this.radii,
      badgeTheme: badgeTheme ?? this.badgeTheme,
      monospace: monospace ?? this.monospace,
    );
  }

  @override
  SoliplexTheme lerp(covariant SoliplexTheme? other, double t) {
    if (other is! SoliplexTheme) return this;
    return SoliplexTheme(
      colors: colors,
      radii: SoliplexRadii.lerp(radii, other.radii, t),
      badgeTheme: badgeTheme,
      monospace: monospace,
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
