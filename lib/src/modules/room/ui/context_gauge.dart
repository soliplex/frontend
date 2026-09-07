import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// Diameter of the painted ring. Smaller than its hit target on purpose —
/// the control has to read as a quiet status dot while still being
/// comfortably tappable.
const _ringDiameter = 18.0;

/// Minimum tap target, per the platform accessibility guidance.
const _hitTarget = 44.0;

/// Fraction above which the ring warns, then alarms.
const _warnAt = 0.75;
const _alarmAt = 0.90;

/// A small ring in the composer showing how full the context window is.
///
/// Three states, because the underlying reading has three:
///
/// - **No window declared** — a hollow dot. The room has not said how large
///   its model's context is, and inventing a denominator would turn an
///   honest count into a confidently wrong percentage.
/// - **Provisional** — a hairline ring. Calibration has not seen enough
///   runs to correct for what the client cannot measure, so the number is
///   known to read low.
/// - **Settled** — a filled arc, tinted neutral, warning, or danger.
class ContextGauge extends StatelessWidget {
  /// Creates a gauge.
  const ContextGauge({
    required this.usage,
    this.onTap,
    super.key,
  });

  /// The current reading.
  final ContextUsage usage;

  /// Opens the breakdown. Null disables the control.
  final VoidCallback? onTap;

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
      button: true,
      label: _semanticsLabel,
      child: Tooltip(
        message: _tooltip,
        child: InkResponse(
          onTap: onTap,
          radius: _hitTarget / 2,
          child: SizedBox(
            width: _hitTarget,
            height: _hitTarget,
            child: Center(
              child: CustomPaint(
                size: const Size.square(_ringDiameter),
                painter: _RingPainter(
                  fraction: fraction,
                  color: color,
                  trackColor: scheme.outlineVariant,
                  isProvisional: usage.isProvisional,
                ),
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
    required this.isProvisional,
  });

  final double? fraction;
  final Color color;
  final Color trackColor;
  final bool isProvisional;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1.5;
    final strokeWidth = isProvisional ? 1.0 : 2.0;

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
      old.trackColor != trackColor ||
      old.isProvisional != isProvisional;
}
