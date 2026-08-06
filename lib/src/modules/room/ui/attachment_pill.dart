import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// An attachment named inline in a sentence, at the position it was written.
///
/// Text-scale by construction. An image at its own scale contributes its whole
/// box to the line it sits in, so the line grows to fit it and the paragraph's
/// rhythm breaks on that one line; the pill stands in for the image in the flow
/// and the image itself is shown at size elsewhere. This is why the pill is the
/// composer's placeholder widget and the bubble's attachment marker both — the
/// job is the same in either place.
///
/// [description] is the whole announcement for the slot. The glyph carries the
/// meaning visually and there is no room to render the description inline
/// without breaking the sentence, so it is carried two ways: as the screen
/// reader's label, and as a tooltip for everyone else.
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

  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background =
        isError ? colors.errorContainer : colors.secondaryContainer;
    final foreground =
        isError ? colors.onErrorContainer : colors.onSecondaryContainer;

    Widget pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(context.radii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foreground),
          if (label != null) ...[
            const SizedBox(width: SoliplexSpacing.s1),
            Text(
              label!,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: foreground),
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
