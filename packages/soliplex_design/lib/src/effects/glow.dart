import 'package:flutter/material.dart';

/// A soft radial glow rendered *behind* [child] — a backplate for brand
/// artwork that can't be inverted for the current theme (institutional
/// logos, non-monochrome marks).
///
/// The glow is a [RadialGradient] that bleeds outside the widget's layout
/// bounds, so [SoliplexGlow] takes exactly [child]'s size and does not
/// disturb surrounding layout. The glow is brightest at the center and
/// fades to fully transparent at its rim.
///
/// The halo scales with [child]: it fills the child's box and is enlarged by
/// [extentFactor], so the same mark reads correctly whether it's a 24px logo
/// in a top bar or a 96px one on a sign-in screen.
class SoliplexGlow extends StatelessWidget {
  const SoliplexGlow({
    required this.color,
    required this.child,
    super.key,
    this.extentFactor = 0.25,
  });

  /// Color of the glow at its center; fades to transparent at the rim.
  final Color color;

  final Widget child;

  /// How far the glow radiates beyond each edge of [child], as a fraction of
  /// the child's size. `0.25` (the default) grows the backplate to 1.5× the
  /// child — a quarter of its size bleeding past every edge.
  final double extentFactor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        // Fill the child's box, then scale past it so the halo stays
        // proportional to the mark at any size.
        Positioned.fill(
          child: Transform.scale(
            scale: 1 + 2 * extentFactor,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [color, color.withAlpha(0)],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
