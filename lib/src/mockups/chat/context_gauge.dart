// Copied from lib/src/modules/room/ui/context_gauge.dart on
// feat/server-measured-context, plus [ContextRing] for the thread panel.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'context_usage.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// Diameter of the painted ring. Smaller than the box it sits in on
/// purpose — it has to read as a quiet status dot beside the send button,
/// not compete with it.
const _ringDiameter = 18.0;

/// Footprint the ring reserves in the composer row.
const _slotSize = 44.0;

/// Fraction above which the ring warns, then alarms.
const _warnAt = 0.75;
const _alarmAt = 0.90;

/// A small ring in the composer showing how full the context window is.
///
/// Two states, because the underlying reading has two:
///
/// - **No window reported** — a hollow dot. The provider has not said how
///   large the model's context is, and inventing a denominator would turn
///   an honest count into a confidently wrong percentage.
/// - **Measured** — a filled arc, tinted neutral, warning, or danger.
///
/// It reports rather than acts: there is nothing behind it to open, so it
/// is not a button and does not take focus.
class ContextGauge extends StatelessWidget {
  /// Creates a gauge.
  const ContextGauge({
    required this.usage,
    super.key,
  });

  /// The current reading.
  final ContextUsage usage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = usage.fractionUsed;

    final color = switch (fraction) {
      null => scheme.onSurfaceVariant,
      final f when f >= _alarmAt => context.danger,
      final f when f >= _warnAt => context.warning,
      _ => scheme.primary,
    };

    return Semantics(
      label: _semanticsLabel,
      child: Tooltip(
        message: _tooltip,
        child: SizedBox(
          width: _slotSize,
          height: _slotSize,
          child: Center(
            child: CustomPaint(
              size: const Size.square(_ringDiameter),
              painter: _RingPainter(
                fraction: fraction,
                color: color,
                trackColor: scheme.outlineVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _semanticsLabel {
    final fraction = usage.fractionUsed;
    if (fraction == null) {
      return 'Context usage: ${usage.tokens} tokens. '
          'No context window declared.';
    }
    return 'Context usage: ${(fraction * 100).round()} percent of the '
        'context window.';
  }

  String get _tooltip {
    final fraction = usage.fractionUsed;
    final approx = usage.isApproximate ? '~' : '';
    if (fraction == null) {
      return '$approx${usage.tokens} tokens used';
    }
    return '$approx${(fraction * 100).round()}% of context used';
  }
}

/// The ring at a size that carries a label, split by [ContextShare] — where
/// the tokens came from — with the free part of the window painted well
/// clear of the surface so it reads as room to spare, not as a gap.
class ContextRing extends StatelessWidget {
  const ContextRing({
    required this.usage,
    this.diameter = 72,
    this.strokeWidth = 8,
    super.key,
  });

  final ContextUsage usage;
  final double diameter;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = usage.fractionUsed;
    final palette = contextShareColors(context);
    final labelColor = switch (fraction) {
      null => scheme.onSurfaceVariant,
      final f when f >= _alarmAt => context.danger,
      final f when f >= _warnAt => context.warning,
      _ => scheme.onSurface,
    };
    // Shares as fractions of the whole window (or of the count, without
    // one), in the enum's order so the ring and the legend agree.
    final denominator = usage.contextWindow ?? usage.tokens;
    final segments = <(Color, double)>[
      for (final share in ContextShare.values)
        if ((usage.byShare[share] ?? 0) > 0 && denominator > 0)
          (palette[share]!, usage.byShare[share]! / denominator),
    ];
    return SizedBox.square(
      dimension: diameter,
      child: CustomPaint(
        painter: _SegmentedRingPainter(
          segments: segments,
          trackColor: freeSpaceColor(context),
          strokeWidth: strokeWidth,
        ),
        child: Center(
          child: Text(
            fraction == null ? '—' : '${(fraction * 100).round()}%',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: labelColor,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ),
    );
  }
}

/// One colour per share, solved for contrast against the surface.
///
/// Carried over from the breakdown on feat/server-measured-context: the
/// scheme's primary/secondary/tertiary are near-neutral in this brand, so a
/// ring drawn from them was five shades of the same grey. The hues come from
/// the three symbolic colours instead, at two tones each; every tone clears
/// 3:1 against the surface in both themes, which is what WCAG 1.4.11 asks of
/// a graphical object that carries meaning.
Map<ContextShare, Color> contextShareColors(BuildContext context) {
  final tone = _Tone(Theme.of(context).colorScheme);
  return {
    // The two that dominate an ordinary thread get the two most distinct
    // hues, so the shape of a conversation reads at a glance.
    ContextShare.human: tone.of(context.success, _Depth.base),
    ContextShare.llm: tone.of(context.success, _Depth.deep),
    ContextShare.system: tone.of(context.info, _Depth.base),
    ContextShare.rag: tone.of(context.info, _Depth.deep),
    ContextShare.tools: tone.of(context.warning, _Depth.base),
  };
}

/// The unused part of the window. Not the surface: painted the colour of
/// what is behind it, the free wedge reads as a gap in the ring rather than
/// as room to spare.
Color freeSpaceColor(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return _Tone(scheme).free(scheme.outlineVariant);
}

enum _Depth {
  deep(7.0),
  base(4.8);

  const _Depth(this.contrast);

  final double contrast;
}

const _freeSpaceContrast = 2.1;

/// Solves a hue's lightness for a target contrast against the surface, by
/// bisection over the full lightness scale.
class _Tone {
  _Tone(ColorScheme scheme) : _surface = scheme.surface;

  final Color _surface;

  Color of(Color hue, _Depth depth) => _at(hue, depth.contrast);

  Color free(Color neutral) => _at(neutral, _freeSpaceContrast);

  Color _at(Color hue, double target) {
    final hsl = HSLColor.fromColor(hue);
    final towardsBlack = _surface.computeLuminance() > 0.5;
    var lo = 0.0;
    var hi = 1.0;
    // A hue that cannot reach the target even at the extreme settles at
    // the extreme, which is the most contrast it has to give.
    for (var i = 0; i < 24; i++) {
      final mid = (lo + hi) / 2;
      final candidate = hsl.withLightness(mid).toColor();
      if (_contrast(candidate, _surface) > target) {
        if (towardsBlack) {
          lo = mid;
        } else {
          hi = mid;
        }
      } else if (towardsBlack) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    return hsl.withLightness((lo + hi) / 2).toColor();
  }
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// Consecutive arcs from twelve o'clock, one per share, over a full track
/// in the free-space colour; a hairline gap between arcs keeps neighbours
/// of the same hue apart.
class _SegmentedRingPainter extends CustomPainter {
  const _SegmentedRingPainter({
    required this.segments,
    required this.trackColor,
    required this.strokeWidth,
  });

  final List<(Color, double)> segments;
  final Color trackColor;
  final double strokeWidth;

  static const _gap = 0.035;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    const strokeWidth = 2.0;
    final radius = size.width / 2 - strokeWidth / 2 - 0.5;
    final rect = Rect.fromCircle(center: centre, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    canvas.drawCircle(centre, radius, paint..color = trackColor);

    var start = -math.pi / 2;
    for (final (color, fraction) in segments) {
      final sweep = 2 * math.pi * fraction;
      final drawn = math.max(0.0, sweep - _gap);
      if (drawn > 0) {
        canvas.drawArc(rect, start, drawn, false, paint..color = color);
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_SegmentedRingPainter old) =>
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth ||
      old.segments.length != segments.length ||
      Iterable.generate(segments.length)
          .any((i) => old.segments[i] != segments[i]);
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.fraction,
    required this.color,
    required this.trackColor,
  });

  final double? fraction;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    const strokeWidth = 2.0;
    final radius = size.width / 2 - strokeWidth / 2 - 0.5;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = trackColor;

    canvas.drawCircle(centre, radius, track);

    final value = fraction;
    if (value == null || value <= 0) return;

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;

    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.trackColor != trackColor;
}
