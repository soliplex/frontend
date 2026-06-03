import 'package:flutter/material.dart';

import 'package:soliplex_design/src/tokens/spacing.dart';

/// Shared pill chrome for the badge family: a rounded tinted surface
/// carrying a label and an optional leading icon.
///
/// Package-internal — **not exported** from the barrel. Callers
/// (`SoliplexBadge`, `SoliplexClassificationBadge`) resolve their own
/// colors from whatever source is appropriate (intent tokens vs. a
/// configured classification level) and hand the pill the finished
/// values, so the pill itself is colour-source agnostic. [foreground] is
/// applied to both the text style and the icon.
class BadgePill extends StatelessWidget {
  const BadgePill({
    required this.label,
    required this.background,
    required this.foreground,
    required this.padding,
    required this.radius,
    required this.textStyle,
    this.icon,
    super.key,
  });

  final Widget label;
  final Color background;
  final Color foreground;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Base text style; its color is overridden by [foreground].
  final TextStyle textStyle;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final style = textStyle.copyWith(color: foreground);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: DefaultTextStyle.merge(
        style: style,
        child: IconTheme.merge(
          data: IconThemeData(color: foreground, size: style.fontSize),
          child: icon == null
              ? label
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon!,
                    const SizedBox(width: SoliplexSpacing.s1),
                    // Flexible so a long label wraps within a constrained
                    // pill instead of overflowing. Loose fit keeps the
                    // natural size when the pill is unbounded, so short
                    // badges are unaffected.
                    Flexible(child: label),
                  ],
                ),
        ),
      ),
    );
  }
}
