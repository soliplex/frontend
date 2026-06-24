import 'dart:math' as math;
import 'dart:ui';

/// WCAG relative-luminance contrast ratio between [a] and [b], in `[1, 21]`.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// The more readable of the brand's near-white / near-black tones on
/// [background], chosen by WCAG contrast ratio. Used to fill an on-color a
/// brand leaves unspecified.
Color readableOn(Color background) {
  const light = Color(0xFFFFFFFF);
  const dark = Color(0xFF0A0A0A);
  return contrastRatio(light, background) >= contrastRatio(dark, background)
      ? light
      : dark;
}
