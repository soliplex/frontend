import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// The frame every entry of a file list shares: uploads, workspace files and
/// workspace folders.
///
/// Every entry is at least one [FileRowAction] tall, so a one-line entry is
/// the same height with or without actions, and an action's touch target
/// spans it. A failed entry, two lines tall, is tinted, and keeps the same
/// side padding so its icons stay in the columns of its neighbours.
///
/// The tint and the actions' highlights are drawn on the nearest [Material],
/// so place the row on one with nothing opaque between them, inside any
/// scroll view the row is in: the file panel and room info's card do.
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

  /// Null disables the action, as a download's outcome does while it shows.
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

/// A file's or folder's name, as a file manager shows one: it labels the
/// entry rather than being text to select, and its full name, which a cut
/// name hides, shows on hover or, on touch, a long press.
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

/// A [ProgressRing] in an action's place, while the work that action started
/// is under way.
class FileRowActionProgress extends StatelessWidget {
  const FileRowActionProgress({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: FileRowAction.extent,
      child: Center(child: ProgressRing(label: label)),
    );
  }
}

/// A progress ring in a 16 px icon slot, drawn the size of an icon's shape
/// rather than its box, so it weighs as much as the icons beside it, and
/// named by [label] to a screen reader. Indeterminate when [value] is null.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.label, this.value});

  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    final ring = SizedBox.square(
      dimension: 16,
      child: Center(
        child: SizedBox.square(
          dimension: 12,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: value,
            semanticsLabel: label,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
    if (value != null) return ring;
    // A status, which a browser announces; a spinner's own role carries the
    // label to no reader there.
    return Semantics(
      container: true,
      role: SemanticsRole.status,
      label: label,
      excludeSemantics: true,
      child: ring,
    );
  }
}
