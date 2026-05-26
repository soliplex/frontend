import 'package:flutter/material.dart';

import 'package:soliplex_design/src/components/badge/intent.dart';
import 'package:soliplex_design/src/theme/theme_extensions.dart';
import 'package:soliplex_design/src/tokens/spacing.dart';

/// An inline status pill — a small rounded surface carrying a short label
/// and optional leading icon, tinted by [BadgeIntent].
///
/// Distinct from Material's [Badge], which is a *positional* indicator
/// (typically overlaid on another widget — an unread count over an
/// avatar). [SoliplexBadge] is *inline*: it flows as part of normal text
/// or row layouts (a "v2" next to a name, a "draft" beside a title).
///
/// For decorative tags use [BadgeIntent.neutral]; for status pills use
/// `info`/`success`/`warning`/`danger`.
class SoliplexBadge extends StatelessWidget {
  const SoliplexBadge({
    required this.label,
    super.key,
    this.icon,
    this.intent = BadgeIntent.neutral,
  });

  /// The label widget (typically a [Text]). Kept as a [Widget] rather than
  /// a `String` so callers can drop in [Text.rich], custom styles, or
  /// localised widgets without an extra constructor.
  final Widget label;

  /// Optional leading icon, rendered at the label's font size.
  final Widget? icon;

  /// Semantic role — defaults to [BadgeIntent.neutral].
  final BadgeIntent intent;

  @override
  Widget build(BuildContext context) {
    final colors = badgeIntentColors(intent, context);
    final theme = SoliplexTheme.of(context);
    final textStyle = theme.badgeTheme.textStyle.copyWith(
      color: colors.foreground,
    );

    return Container(
      padding: theme.badgeTheme.padding,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(theme.radii.sm),
      ),
      child: DefaultTextStyle.merge(
        style: textStyle,
        child: IconTheme.merge(
          data: IconThemeData(
            color: colors.foreground,
            size: textStyle.fontSize,
          ),
          child: icon == null
              ? label
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon!,
                    const SizedBox(width: SoliplexSpacing.s1),
                    label,
                  ],
                ),
        ),
      ),
    );
  }
}
