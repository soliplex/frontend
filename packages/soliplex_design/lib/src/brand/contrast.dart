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

/// The more readable of white or black on [background], chosen by WCAG contrast
/// ratio. Used to fill an on-color a brand leaves unspecified.
///
/// The dark candidate is pure black, not the softer `#0A0A0A` foreground tone,
/// so the better of the two choices clears AA 4.5:1 for *any* surface (worst
/// case ≈4.58:1 at mid luminance). `#0A0A0A` would bottom out at ≈4.45:1,
/// letting a mid-tone surface derive a sub-AA foreground.
Color readableOn(Color background) {
  const light = Color(0xFFFFFFFF);
  const dark = Color(0xFF000000);
  return contrastRatio(light, background) >= contrastRatio(dark, background)
      ? light
      : dark;
}
