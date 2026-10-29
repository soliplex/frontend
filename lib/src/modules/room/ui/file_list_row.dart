import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// The frame every entry of a file list shares: uploads, workspace files and
/// workspace folders.
///
/// Every entry is one [FileRowAction] tall, with or without actions, so a
/// list of mixed entries keeps one rhythm and an action's touch target spans
/// its row. A failed entry is tinted, and keeps the same side padding so its
/// icons stay in the columns of its neighbours.
class FileListRow extends StatelessWidget {
  const FileListRow({
    super.key,
    required this.leading,
    required this.content,
    this.actions = const [],
    this.isFailed = false,
  });

  final Widget leading;
  final Widget content;
  final List<Widget> actions;

  final bool isFailed;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Keeps the tints of two failed entries apart.
      margin: isFailed
          ? const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1)
          : null,
      // A failed entry's name and reason fill an action's height, so its tint
      // needs room above and below them.
      padding: EdgeInsets.symmetric(
        horizontal: SoliplexSpacing.s1,
        vertical: isFailed ? SoliplexSpacing.s1 : 0,
      ),
      decoration: isFailed
          ? BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(context.radii.sm),
            )
          : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: FileRowAction.extent),
        child: Row(
          children: [
            leading,
            const SizedBox(width: SoliplexSpacing.s2),
            Expanded(child: content),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// A trailing action of a [FileListRow]: a small icon in a touch target as
/// tall as the row, named once to a screen reader. Neighbouring targets
/// touch; their padding keeps the icons apart.
///
/// Its own semantics node, so a card that merges its children's semantics
/// does not absorb it and become a button itself; the tooltip is left out of
/// semantics so the label is not read twice.
class FileRowAction extends StatelessWidget {
  const FileRowAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  /// The side of every action, and so the least height of a row.
  static const double extent = _iconSize + 2 * SoliplexSpacing.s2;
  static const double _iconSize = 16;

  final IconData icon;
  final String tooltip;

  /// Null disables the action, as a download in flight does.
  final VoidCallback? onTap;

  /// Defaults to the muted `onSurfaceVariant`.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(context.radii.sm),
          child: Padding(
            padding: const EdgeInsets.all(SoliplexSpacing.s2),
            child: Icon(
              icon,
              size: _iconSize,
              color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
