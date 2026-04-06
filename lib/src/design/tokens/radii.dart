import 'dart:ui';

class SoliplexRadii {
  const SoliplexRadii({
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
  });

  factory SoliplexRadii.lerp(SoliplexRadii a, SoliplexRadii b, double t) =>
      SoliplexRadii(
        sm: lerpDouble(a.sm, b.sm, t)!,
        md: lerpDouble(a.md, b.md, t)!,
        lg: lerpDouble(a.lg, b.lg, t)!,
        xl: lerpDouble(a.xl, b.xl, t)!,
      );

  final double sm;
  final double md;
  final double lg;
  final double xl;
}

const soliplexRadii = SoliplexRadii(sm: 2, md: 8, lg: 12, xl: 20);
