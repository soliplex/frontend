import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// The background and foreground an attachment marker is painted in.
///
/// Shared so that a pill and the badge on the tile it names cannot drift
/// apart: they are the same number in two places and have to look like it.
({Color background, Color foreground}) attachmentToneColors(
  ColorScheme colors, {
  required bool isError,
}) =>
    isError
        ? (
            background: colors.errorContainer,
            foreground: colors.onErrorContainer,
          )
        : (
            background: colors.secondaryContainer,
            foreground: colors.onSecondaryContainer,
          );

/// A text-scale marker naming one attachment, at the position it was written.
///
/// Text-scale is the whole point. An element in a line of text contributes its
/// full height to that line, so anything taller than the line box swells one
/// line and breaks the paragraph around it; the marker stands in for an
/// attachment in the flow while the attachment itself is shown at size
/// elsewhere, or — in the composer, where there is no thumbnail — stands as the
/// attachment's whole representation. At `labelSmall` with no vertical padding
/// and a hairline border this is 20 px against a 24 px `bodyMedium` line, so it
/// costs the paragraph nothing.
///
/// [description] is the whole announcement for the slot. The glyph carries the
/// meaning visually and there is no room to render the description inline, so
/// it is carried two ways: as the screen reader's label, and as a tooltip for
/// everyone else.
///
/// **Not built on `SoliplexBadge`, deliberately.** The design system's rule is
/// to prefer the branded component; `SoliplexBadge` renders at `labelMedium`
/// (14 at 1.5 = 21 px) inside `badgeTheme.padding` (4 px top and bottom), so it
/// stands 29 px tall. Placed inline it would push the 24 px line box to 29 and
/// reintroduce the swelling this widget exists to avoid. Its `danger` intent is
/// the same `errorContainer` pair used here; its `neutral` intent is a 6% ink
/// wash, which reads fainter still on a tinted bubble. If the badge ever grows
/// a dense variant that fits a line box, prefer it.
class AttachmentPill extends StatelessWidget {
  /// Creates a pill for an attachment that is present.
  const AttachmentPill({
    super.key,
    required this.icon,
    required this.description,
    this.label,
    this.onTap,
  }) : isError = false;

  /// Creates a pill for an attachment that cannot be shown.
  const AttachmentPill.error({
    super.key,
    required this.icon,
    required this.description,
    this.label,
    this.onTap,
  }) : isError = true;

  /// The glyph standing in for the attachment.
  final IconData icon;

  /// What this slot is, in full. Announced, and shown on hover or long-press.
  final String description;

  /// Text beside the glyph. Null renders the glyph alone.
  final String? label;

  /// Null renders a pill that is not interactive — nothing to open, nothing to
  /// remove.
  final VoidCallback? onTap;

  /// Whether this marks a slot that cannot be shown.
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = attachmentToneColors(theme.colorScheme, isError: isError);

    Widget pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s1),
      decoration: BoxDecoration(
        color: tone.background,
        // The pill sits on two different surfaces — the composer's field and a
        // tinted message bubble — and its fill is close enough to the bubble's
        // to disappear into it. An outline gives it an edge on either, where
        // any single fill would have to lose against one of them.
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(context.radii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: tone.foreground),
          if (label != null) ...[
            const SizedBox(width: SoliplexSpacing.s1),
            Text(
              label!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: tone.foreground,
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap != null) {
      pill = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: pill,
      );
    }

    return Semantics(
      button: onTap != null,
      label: description,
      child: Tooltip(
        message: description,
        // Announced by the Semantics above; a tooltip that contributed it too
        // would have a screen reader read the pill twice.
        excludeFromSemantics: true,
        child: pill,
      ),
    );
  }
}
