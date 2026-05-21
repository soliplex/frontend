import 'package:flutter/material.dart';

/// A soft radial glow rendered *behind* [child] — a backplate for brand
/// artwork that can't be inverted for the current theme (institutional
/// logos, non-monochrome marks).
///
/// The glow is a [RadialGradient] that bleeds outside the widget's layout
/// bounds, so [SoliplexGlow] takes exactly [child]'s size and does not
/// disturb surrounding layout. The glow is brightest at the center and
/// fades to fully transparent at its rim.
class SoliplexGlow extends StatelessWidget {
  const SoliplexGlow({
    super.key,
    required this.color,
    required this.child,
    this.extent = 16,
  });

  /// Color of the glow at its center; fades to transparent at the rim.
  final Color color;

  /// How far the glow radiates beyond each edge of [child], in logical
  /// pixels.
  final double extent;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Positioned(
          left: -extent,
          right: -extent,
          top: -extent,
          bottom: -extent,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [color, color.withAlpha(0)],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
