import 'package:flutter/material.dart';

import 'package:soliplex_design/src/tokens/colors.dart';
import 'package:soliplex_design/src/tokens/marking_colors.dart';
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
    this.markingColors = SoliplexMarkingColors.dod,
  });

  final SoliplexColors colors;
  final SoliplexRadii radii;
  final SoliplexBadgeThemeData badgeTheme;

  /// Classification marking palette. Defaults to [SoliplexMarkingColors.dod];
  /// white-label flavors override it via the theme factory.
  final SoliplexMarkingColors markingColors;

  @override
  SoliplexTheme copyWith({
    SoliplexColors? colors,
    SoliplexRadii? radii,
    SoliplexBadgeThemeData? badgeTheme,
    SoliplexMarkingColors? markingColors,
  }) {
    return SoliplexTheme(
      colors: colors ?? this.colors,
      radii: radii ?? this.radii,
      badgeTheme: badgeTheme ?? this.badgeTheme,
      markingColors: markingColors ?? this.markingColors,
    );
  }

  @override
  SoliplexTheme lerp(covariant SoliplexTheme? other, double t) {
    if (other is! SoliplexTheme) return this;
    return SoliplexTheme(
      colors: colors,
      radii: SoliplexRadii.lerp(radii, other.radii, t),
      badgeTheme: badgeTheme,
      // Marking colors are authoritative and snap (matching how `colors`
      // is handled) rather than cross-fading during theme transitions.
      markingColors: markingColors,
    );
  }

  static SoliplexTheme of(BuildContext context) {
    return Theme.of(context).extension<SoliplexTheme>()!;
  }

  /// The active marking palette, falling back to [SoliplexMarkingColors.dod]
  /// when no [SoliplexTheme] extension is installed (e.g. a host app or test
  /// using a bare `ThemeData`). Marking surfaces resolve colors through this
  /// so they render correctly with or without the full brand theme.
  static SoliplexMarkingColors markingColorsOf(BuildContext context) {
    return Theme.of(context).extension<SoliplexTheme>()?.markingColors ??
        SoliplexMarkingColors.dod;
  }
}
