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
  });

  final SoliplexColors colors;
  final SoliplexRadii radii;
  final SoliplexBadgeThemeData badgeTheme;

  @override
  SoliplexTheme copyWith({
    SoliplexColors? colors,
    SoliplexRadii? radii,
    SoliplexBadgeThemeData? badgeTheme,
  }) {
    return SoliplexTheme(
      colors: colors ?? this.colors,
      radii: radii ?? this.radii,
      badgeTheme: badgeTheme ?? this.badgeTheme,
    );
  }

  @override
  SoliplexTheme lerp(covariant SoliplexTheme? other, double t) {
    if (other is! SoliplexTheme) return this;
    return SoliplexTheme(
      colors: colors,
      radii: SoliplexRadii.lerp(radii, other.radii, t),
      badgeTheme: badgeTheme,
    );
  }

  static SoliplexTheme of(BuildContext context) {
    return Theme.of(context).extension<SoliplexTheme>()!;
  }
}
