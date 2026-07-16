import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:soliplex_design/src/tokens/colors.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

/// WCAG relative-luminance contrast ratio between [a] and [b], in `[1, 21]`.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Minimum WCAG AA contrast for normal text; an explicit pair below it is used
/// as-is and logged, not altered.
const double minContrast = 4.5;

/// Contrast floor for de-emphasized (`mutedForeground`) text (WCAG 3:1 UI bar).
const double minMutedContrast = 3;

final Logger _contrastLog =
    LogManager.instance.getLogger('soliplex_design.BrandTheme');

/// Warns for each foreground/background pair below its contrast floor. Runs for
/// every theme built via `buildSoliplexThemeData`, so both the curated and the
/// direct (fork) paths are checked. `link` is checked separately in
/// `lowerBrandTheme` (only when a brand sets it). Colors are used as-is
/// regardless; warnings drop silently if no LogManager sink is attached.
void warnLowContrast(SoliplexColors c, Brightness brightness) {
  void check(String role, Color fg, Color bg, {double min = minContrast}) {
    final ratio = contrastRatio(fg, bg);
    if (ratio >= min) return;
    _contrastLog.warning(
      'BrandTheme "$role" contrast is ${ratio.toStringAsFixed(2)}:1 in the '
      '${brightness.name} palette, below ${min.toStringAsFixed(1)}:1. The '
      'supplied color is used as-is; verify it is legible.',
      attributes: {'role': role, 'ratio': ratio, 'brightness': brightness.name},
    );
  }

  check('onPrimary', c.onPrimary, c.primary);
  check('onSecondary', c.onSecondary, c.secondary);
  check('onTertiary', c.onTertiary, c.tertiary);
  check('onError', c.onDestructive, c.destructive);
  check('onErrorContainer', c.onErrorContainer, c.errorContainer);
  check('onSuccessContainer', c.onSuccessContainer, c.successContainer);
  check('onWarningContainer', c.onWarningContainer, c.warningContainer);
  check('onInfoContainer', c.onInfoContainer, c.infoContainer);
  check('foreground', c.foreground, c.background);
  check('mutedForeground', c.mutedForeground, c.muted, min: minMutedContrast);
}

// Softest-first foreground cascades. Each side ends in a pure tone whose
// contrast against any surface it is chosen for never drops below ≈4.58:1 (the
// minimum, at the black/white crossover), so the loop in [readableOn] is always
// able to find a tone clearing AA — it never falls through to a sub-AA result.
// The returned tone itself is only guaranteed ≥4.5:1: a near-tone is accepted
// as soon as it clears that floor, so a returned pair can sit right at 4.5. The
// softer near-tones are preferred because pure black/white is harsher on the
// eyes; a pure tone is the last resort, reached only on a mid-tone surface
// where even the near-tone dips below AA.
const List<Color> _darkInk = [
  Color(0xFF212427),
  Color(0xFF0A0A0A),
  Color(0xFF000000),
];
const List<Color> _lightInk = [Color(0xFFFAFAFA), Color(0xFFFFFFFF)];

/// The most readable foreground for [surface], chosen by WCAG contrast.
///
/// Picks the dark or light side by contrast, then returns the **softest** tone
/// on that side that still clears AA (4.5:1) — preferring a near-black
/// (`#212427`) or near-white (`#FAFAFA`) over pure black/white, which reads
/// easier and only escalates to a pure tone on a mid-tone surface.
///
/// When [tintHue] is a chromatic color and [tintStrength] > 0, the soft
/// near-tone is nudged toward that hue (lightness preserved), giving a tonal
/// on-color that harmonizes with the surface or brand. The tint is just the top
/// rung of the cascade: if it would fall below AA it is dropped for the
/// untinted tone. A null or achromatic [tintHue], or zero strength, adds none.
///
/// For a decorative tint that should match the foreground tone rather than
/// guarantee AA, see `contrastingForeground` in `tokens/colors.dart`.
Color readableOn(Color surface, {Color? tintHue, double tintStrength = 0}) {
  final useDark = contrastRatio(_darkInk.last, surface) >=
      contrastRatio(_lightInk.last, surface);
  final cascade = useDark ? _darkInk : _lightInk;
  final tinted = _tinted(cascade.first, tintHue, tintStrength);
  final candidates = tinted == null ? cascade : <Color>[tinted, ...cascade];
  for (final tone in candidates) {
    if (contrastRatio(tone, surface) >= minContrast) return tone;
  }
  return cascade.last;
}

/// The soft [base] tone nudged toward [hue]'s hue at [strength] saturation, its
/// lightness preserved. Returns null when there is no hue to borrow — a null or
/// achromatic [hue], or zero [strength] — so the caller keeps the neutral tone.
Color? _tinted(Color base, Color? hue, double strength) {
  if (hue == null || strength <= 0) return null;
  final source = HSLColor.fromColor(hue);
  if (source.saturation < 0.05) return null;
  final tone = HSLColor.fromColor(base);
  return tone.withHue(source.hue).withSaturation(strength).toColor();
}
