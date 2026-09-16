import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// Diameter of the painted ring. Smaller than the box it sits in on
/// purpose — it has to read as a quiet status dot beside the send button,
/// not compete with it.
const _ringDiameter = 18.0;

/// Footprint the ring reserves in the composer row.
const _slotSize = 44.0;

/// A small ring in the composer showing how full the context window is.
///
/// Two states, because the ring has two:
///
/// - **No percentage available** — a hollow dot. Either the provider has
///   not said how large the model's context is, or nothing has counted
///   what the thread already occupies. Inventing either half would turn
///   an honest gap into a confidently wrong percentage.
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

    // The reading says how much attention it deserves; this only picks
    // the colour for it. Deciding here as well is how the ring came to
    // warn at a fraction the banner did not.
    final color = switch (fraction) {
      null => scheme.onSurfaceVariant,
      _ when usage.isCritical => context.danger,
      _ when usage.isNearlyFull => context.warning,
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
    if (fraction != null) {
      return 'Context usage: ${(fraction * 100).round()} percent of the '
          'context window.';
    }
    final counted = usage.tokens;
    // Nothing has counted the thread, so the estimate on its own is a
    // fragment of a conversation of unknown size, not a reading of it.
    if (counted == null) return 'Context usage has not been measured yet.';
    // Reports the missing percentage without naming a cause: a model
    // that declares no window lands here with a real count.
    return 'Context usage: $counted tokens; no percentage available.';
  }

  String get _tooltip {
    final fraction = usage.fractionUsed;
    final approx = usage.isApproximate ? '~' : '';
    if (fraction != null) {
      return '$approx${(fraction * 100).round()}% of context used';
    }
    final counted = usage.tokens;
    if (counted == null) return 'Context usage not measured yet';
    return '$approx$counted tokens used';
  }
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
    final radius = size.width / 2 - 1.5;
    const strokeWidth = 2.0;

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
