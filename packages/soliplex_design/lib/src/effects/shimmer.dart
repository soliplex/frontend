import 'dart:async';

import 'package:flutter/material.dart';

import 'package:soliplex_design/src/theme/theme_extensions.dart';
import 'package:soliplex_design/src/tokens/spacing.dart';

/// An animated skeleton placeholder: a stack of rounded "text" bars with a
/// light-sweep travelling across them.
///
/// Use it where content is being produced but cannot be revealed incrementally
/// — e.g. an assistant chat bubble waiting on a non-streamed response — as a
/// richer stand-in than a bare spinner. The bars fill the available width
/// (each scaled by its [lineFractions] entry), so place [SoliplexShimmer] in a
/// width-bounded parent.
///
/// Colors default to a faint, theme-aware neutral so the effect reads in both
/// light and dark; the moving beam brightens where it overlaps the resting
/// fill. Override [baseColor] / [shineColor] to tune it for a specific surface.
class SoliplexShimmer extends StatefulWidget {
  const SoliplexShimmer({
    super.key,
    this.lineFractions = const [1, 1, 1, 0.55],
    this.lineHeight = 14,
    this.lineSpacing = SoliplexSpacing.s3,
    this.borderRadius,
    this.baseColor,
    this.shineColor,
    this.beamWidthFraction = 0.35,
    this.period = const Duration(milliseconds: 1600),
    this.linePhaseOffset = -0.06,
  });

  /// Width of each bar as a fraction (0–1) of the available width. The list
  /// length is the number of bars.
  final List<double> lineFractions;

  /// Height of each bar.
  final double lineHeight;

  /// Vertical gap between bars. Defaults to [SoliplexSpacing.s3].
  final double lineSpacing;

  /// Corner radius of each bar. Defaults to the theme's small radius.
  final double? borderRadius;

  /// Resting fill of each bar. Defaults to a faint theme neutral.
  final Color? baseColor;

  /// Peak color of the travelling sweep. Defaults to the same faint neutral as
  /// [baseColor] — the overlap between the two is what makes the beam read.
  final Color? shineColor;

  /// Beam width as a fraction of the available width.
  final double beamWidthFraction;

  /// Duration of one full sweep.
  final Duration period;

  /// Per-bar phase offset (as a fraction of a cycle) that skews the beam from
  /// line to line so the sweep reads as a diagonal rather than a flat front.
  final double linePhaseOffset;

  @override
  State<SoliplexShimmer> createState() => _SoliplexShimmerState();
}

class _SoliplexShimmerState extends State<SoliplexShimmer>
    with SingleTickerProviderStateMixin {
  // Fallback width for an unbounded parent — the bars need a finite width to
  // paint. A bounded parent (the common case) overrides this via LayoutBuilder.
  static const _fallbackWidth = 200.0;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.period);
    unawaited(_controller.repeat());
  }

  @override
  void didUpdateWidget(SoliplexShimmer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) {
      _controller
        ..duration = widget.period
        ..reset();
      unawaited(_controller.repeat());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Degrade gracefully outside the brand theme (e.g. a bare MaterialApp):
    // fall back to the standard ColorScheme neutral and the small radius value.
    final soliplex = SoliplexTheme.maybeOf(context);
    final neutralSource = soliplex?.colors.mutedForeground ??
        Theme.of(context).colorScheme.onSurfaceVariant;
    final neutral = neutralSource.withValues(alpha: 0.18);
    final base = widget.baseColor ?? neutral;
    final shine = widget.shineColor ?? neutral;
    final radius = widget.borderRadius ?? soliplex?.radii.sm ?? 6.0;

    final lineCount = widget.lineFractions.length;
    final height =
        lineCount * widget.lineHeight + (lineCount - 1) * widget.lineSpacing;

    return LayoutBuilder(
      builder: (context, constraints) {
        final fullWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : _fallbackWidth;
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              size: Size(fullWidth, height),
              painter: _ShimmerPainter(
                lineFractions: widget.lineFractions,
                lineHeight: widget.lineHeight,
                lineSpacing: widget.lineSpacing,
                borderRadius: radius,
                baseColor: base,
                shineColor: shine,
                progress: _controller.value,
                beamWidth: fullWidth * widget.beamWidthFraction,
                fullWidth: fullWidth,
                linePhaseOffset: widget.linePhaseOffset,
              ),
            );
          },
        );
      },
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  const _ShimmerPainter({
    required this.lineFractions,
    required this.lineHeight,
    required this.lineSpacing,
    required this.borderRadius,
    required this.baseColor,
    required this.shineColor,
    required this.progress,
    required this.beamWidth,
    required this.fullWidth,
    required this.linePhaseOffset,
  });

  final List<double> lineFractions;
  final double lineHeight;
  final double lineSpacing;
  final double borderRadius;
  final Color baseColor;
  final Color shineColor;
  final double progress;
  final double beamWidth;
  final double fullWidth;
  final double linePhaseOffset;

  @override
  void paint(Canvas canvas, Size size) {
    final corner = Radius.circular(borderRadius);
    final travel = fullWidth + beamWidth;

    var y = 0.0;
    for (var i = 0; i < lineFractions.length; i++) {
      // Offset each line's beam by i * linePhaseOffset (wrapping at the cycle
      // boundary) so the sweep crosses the block on a diagonal.
      final phase = (progress + i * linePhaseOffset) % 1.0;
      final beamLeft = -beamWidth + phase * travel;
      final beamRect = Rect.fromLTWH(beamLeft, y, beamWidth, lineHeight);

      final lineRect =
          Rect.fromLTWH(0, y, fullWidth * lineFractions[i], lineHeight);
      final rrect = RRect.fromRectAndRadius(lineRect, corner);

      canvas
        ..drawRRect(rrect, Paint()..color = baseColor)
        ..save()
        ..clipRRect(rrect)
        ..drawRect(
          beamRect,
          Paint()
            ..shader = LinearGradient(
              colors: [Colors.transparent, shineColor, Colors.transparent],
              stops: const [0, 0.5, 1],
            ).createShader(beamRect),
        )
        ..restore();

      y += lineHeight + lineSpacing;
    }
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) =>
      old.progress != progress ||
      old.fullWidth != fullWidth ||
      old.baseColor != baseColor ||
      old.shineColor != shineColor;
}
