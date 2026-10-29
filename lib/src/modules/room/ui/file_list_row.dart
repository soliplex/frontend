import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// The frame every entry of a file list shares: uploads, workspace files and
/// workspace folders.
///
/// Every entry is at least one [FileRowAction] tall, so a one-line entry is
/// the same height with or without actions, and an action's touch target
/// spans it. A failed entry, two lines tall, is tinted, and keeps the same
/// side padding so its icons stay in the columns of its neighbours.
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
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: FileRowAction.extent),
      child: Row(
        children: [
          leading,
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(child: content),
          ...actions,
        ],
      ),
    );
    if (!isFailed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s1),
        child: row,
      );
    }
    return Padding(
      // Keeps the tints of two failed entries apart.
      padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
      // An action draws its hover, focus and press highlights on the
      // Material beneath it; Ink paints the tint there too, under them.
      // A failed entry's name and reason stand taller than an action, so
      // the tint also needs room above and below them.
      child: Ink(
        padding: const EdgeInsets.all(SoliplexSpacing.s1),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(context.radii.sm),
        ),
        child: row,
      ),
    );
  }
}

/// A trailing action of a [FileListRow]: a small icon in a touch target as
/// tall as a one-line row, named once to a screen reader. Neighbouring targets
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

/// A file's name, as a file manager shows one: it labels the file rather
/// than being text to select, and its full name, which a cut name hides,
/// shows on hover or, on touch, a long press.
///
/// The tooltip is left out of semantics: the name is already read, by what
/// it wraps or by the row that holds it.
class FullNameTooltip extends StatelessWidget {
  const FullNameTooltip({super.key, required this.name, required this.child});

  final String name;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: name,
      waitDuration: const Duration(milliseconds: 500),
      excludeFromSemantics: true,
      child: SelectionContainer.disabled(child: child),
    );
  }
}
