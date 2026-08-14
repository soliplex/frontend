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
    this.fillHeight = false,
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

  /// Whether the pill grows to whatever height its parent hands it, keeping
  /// its content vertically centred, instead of hugging that content.
  ///
  /// Off by default: a pill in a text row or a card sizes to its label. Turn
  /// it on where the pill is a piece of a bar's furniture and has to line up
  /// with the controls beside it — the caller then owns the height (usually a
  /// `SizedBox`), and without the centring the label would ride the top edge.
  final bool fillHeight;

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
          child: _centred(
            icon == null
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
      ),
    );
  }

  /// Centres [content] in the height the parent forced on the pill.
  /// `widthFactor: 1` keeps the width hugging the content, so only the
  /// vertical axis is filled. A no-op unless [fillHeight] is set — an
  /// unbounded height would otherwise make the align try to fill infinity.
  Widget _centred(Widget content) =>
      fillHeight ? Align(widthFactor: 1, child: content) : content;
}
