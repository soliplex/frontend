import 'dart:async';

import 'package:flutter/material.dart';

import 'package:soliplex_design/src/theme/theme_extensions.dart';

/// Runs a travelling light-sweep across a piece of text to signal that the
/// thing it labels is *in progress* — a calmer, less anxiety-inducing stand-in
/// for a spinner next to every running step.
///
/// Unlike `SoliplexShimmer` (a skeleton of rounded bars for content that has
/// not arrived yet), this shimmers text that is already there: the label of a
/// running tool call, script step, or phase. The resting color of the sweep
/// ([baseColor]) defaults to the muted label neutral, so when a caller swaps
/// this out for a plain [Text] on completion the color does not jump — the row
/// simply stops shimmering.
///
/// The [child] is masked (its own color is irrelevant; the sweep supplies the
/// paint), so pass a `Text` styled from the text theme and let this widget
/// drive the color.
class SoliplexShimmerText extends StatefulWidget {
  const SoliplexShimmerText({
    required this.child,
    super.key,
    this.baseColor,
    this.shineColor,
    this.bandWidth = 0.30,
    this.period = const Duration(milliseconds: 1600),
    this.pauseFraction = 0.35,
  });

  /// The widget to mask — typically a [Text]. Its intrinsic color is replaced
  /// by the sweep, so style everything except the color as usual.
  final Widget child;

  /// Resting color of the text between sweeps. Defaults to the theme's muted
  /// label neutral so it matches an adjacent plain label.
  final Color? baseColor;

  /// Peak color at the crest of the sweep. Defaults to the fuller foreground.
  final Color? shineColor;

  /// Width of the bright band as a fraction (0–1) of the text width.
  final double bandWidth;

  /// Duration of one full sweep-and-pause cycle.
  final Duration period;

  /// Fraction (0–1) of each cycle spent at rest between sweeps.
  final double pauseFraction;

  @override
  State<SoliplexShimmerText> createState() => _SoliplexShimmerTextState();
}

class _SoliplexShimmerTextState extends State<SoliplexShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.period);
    unawaited(_controller.repeat());
  }

  @override
  void didUpdateWidget(SoliplexShimmerText oldWidget) {
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
    // Degrade gracefully outside the brand theme (e.g. a bare MaterialApp).
    final theme = Theme.of(context);
    final soliplex = SoliplexTheme.maybeOf(context);
    final base = widget.baseColor ??
        soliplex?.colors.mutedForeground ??
        theme.colorScheme.onSurfaceVariant;
    final shine = widget.shineColor ?? theme.colorScheme.onSurface;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Remap [0..1] so the sweep runs over the first (1 - pauseFraction) of
        // the cycle then holds at rest for the remainder.
        final active =
            (_controller.value / (1 - widget.pauseFraction)).clamp(0.0, 1.0);
        final travel = 1.0 + widget.bandWidth;
        final center = -widget.bandWidth / 2 + active * travel;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => LinearGradient(
            colors: [base, shine, base],
            stops: [
              (center - widget.bandWidth / 2).clamp(0.0, 1.0),
              center.clamp(0.0, 1.0),
              (center + widget.bandWidth / 2).clamp(0.0, 1.0),
            ],
          ).createShader(rect),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
