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
