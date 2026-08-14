import 'package:flutter/material.dart';

/// A deterministic, theme-aware accent colour derived from [seed].
///
/// The same seed always yields the same hue, so an identity keeps its
/// colour across restarts and across every surface that draws it.
///
/// HSL rather than a swatch table: a fixed hex palette would be a
/// hex-literal violation everywhere outside this package, and a hue
/// wheel gives far more distinct, evenly spread colours than a
/// hand-picked list. Saturation and lightness are tuned per [brightness]
/// so whatever is drawn on top stays legible in both themes.
///
/// Used for room avatars and for labels that have not been given an
/// explicit colour, so the two demonstrably agree rather than drifting
/// apart as separate implementations.
Color hashedHueColor(String seed, Brightness brightness) {
  var hash = 0;
  for (final unit in seed.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return hueColor((hash % 360).toDouble(), brightness);
}

/// Parses a `#RGB` or `#RRGGBB` swatch, or returns null if it cannot.
///
/// For colours that arrive as data — a label's swatch from the server,
/// say — rather than as a token. Lives here so callers outside this
/// package never have to write `Color(0x...)` themselves, which the
/// design-system rules forbid.
///
/// Returns null rather than throwing or substituting a default: a
/// malformed swatch is the caller's cue to fall back to something
/// sensible for its own surface, and a silent black would look
/// deliberate.
Color? colorFromHex(String value) {
  var hex = value.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);

  // Shorthand doubles each digit: '#4D7' means '#44DD77'.
  if (hex.length == 3) {
    hex = hex.split('').map((digit) => '$digit$digit').join();
  }
  if (hex.length != 6) return null;

  final rgb = int.tryParse(hex, radix: 16);
  if (rgb == null) return null;

  return Color(0xFF000000 | rgb);
}

/// The accent colour at [hue] degrees, tuned for [brightness].
///
/// The half of [hashedHueColor] that does not hash, for callers that
/// already have a hue — e.g. one the server derived from a record's own
/// identifier — and only need it rendered consistently with everything
/// else on screen.
Color hueColor(double hue, Brightness brightness) {
  final lightness = brightness == Brightness.dark ? 0.42 : 0.55;
  return HSLColor.fromAHSL(1, hue % 360, 0.55, lightness).toColor();
}
