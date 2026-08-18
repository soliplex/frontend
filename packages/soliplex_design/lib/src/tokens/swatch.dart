import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The grey a label wears until somebody chooses otherwise.
///
/// Neutral in the strict sense — zero saturation — so a label that has
/// never been given a colour reads as *uncoloured* rather than as one
/// more hue competing with the rest. A derived-per-identity default
/// cannot do that: every new label would arrive already shouting.
///
/// One fixed value rather than one per [Brightness], because the swatch
/// is stored on the server and shared between everyone who sees the
/// label. A theme-dependent grey would be written as a different hex
/// depending on which theme the author happened to be using, and the
/// picker would then fail to recognise it as the grey it had offered.
const Color neutralSwatch = Color(0xFF808080);

/// The saturation ceiling for a swatch once it is painted.
///
/// Users pick from a hue wheel, so the raw swatch is fully committed to
/// its hue. Painted at that strength a row of labels out-shouts the
/// thread names it is meant to annotate. Clamping rather than scaling
/// keeps an already-quiet swatch — the neutral grey above, most of all —
/// exactly as quiet as it was.
const double _saturationCeiling = 0.4;

/// Lowers a user-chosen [color] to the three tones a label chip paints.
///
/// A swatch arrives as data: users pick it, and nothing about the theme
/// can anticipate it. Painting it as a solid fill makes every label a
/// focal point, which is the opposite of what an annotation should be.
/// So the chip is drawn the way a quiet tag is drawn everywhere: a
/// barely-there wash of the colour, an outline that carries most of the
/// identity, and text in the colour itself.
///
/// - `fill` — the swatch at low alpha, enough to tint the surface.
/// - `outline` — the swatch at partial alpha, the chip's border.
/// - `content` — label text and icons; opaque, and pushed to a lightness
///   that clears AA against the surface of the [brightness] it is for.
///
/// Returning all three together keeps them derived from one clamped
/// hue: a caller that computed the border separately would drift out of
/// step with the fill the first time either constant moved.
({Color fill, Color outline, Color content}) swatchTint(
  Color color,
  Brightness brightness,
) {
  final isDark = brightness == Brightness.dark;
  final hsl = HSLColor.fromColor(color);
  final muted = hsl.withSaturation(
    math.min(hsl.saturation, _saturationCeiling),
  );

  // The wash and the outline sit at a mid lightness so the hue survives
  // being taken down to a low alpha; the text goes far darker (or far
  // lighter) because it is the only part that has to be read.
  final surface = muted.withLightness(isDark ? 0.6 : 0.45).toColor();
  final content = muted.withLightness(isDark ? 0.82 : 0.3).toColor();

  return (
    fill: surface.withValues(alpha: isDark ? 0.16 : 0.12),
    outline: surface.withValues(alpha: isDark ? 0.45 : 0.38),
    content: content,
  );
}
