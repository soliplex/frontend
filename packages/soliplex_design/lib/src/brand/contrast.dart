import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// WCAG relative-luminance contrast ratio between [a] and [b], in `[1, 21]`.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

const double _minContrast = 4.5;

// Softest-first foreground cascades. Each side ends in a pure tone, which
// always clears AA on the side it is chosen for (worst case ≈4.58:1 at the
// contrast crossover), so the cascade can never bottom out below 4.5:1. The
// softer
// near-tones are preferred because pure black/white is harsher on the eyes;
// a pure tone is the last resort, reached only on a mid-tone surface where
// even the near-tone dips below AA.
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
    if (contrastRatio(tone, surface) >= _minContrast) return tone;
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
