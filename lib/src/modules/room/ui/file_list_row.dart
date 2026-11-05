import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../../../shared/file_size.dart';
import '../../../shared/local_time_format.dart';
import '../../../shared/relative_time.dart';

/// The frame every entry of a file list shares: uploads, workspace files and
/// workspace folders.
///
/// Every entry is at least one [FileRowAction] tall, so a one-line entry is
/// the same height with or without actions, and an action's touch target
/// spans the entry's full height, two-line entries included. A failed entry,
/// two lines tall, is tinted, and keeps the same side padding so its icons
/// stay in the columns of its neighbours.
///
/// An entry given [details] shows them under its [content], with room above
/// and below so the two lines of neighbouring entries stay apart.
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
    this.details,
  });

  final Widget leading;
  final Widget content;

  /// [FileRowAction]s, a [FileRowActionProgress] in one's place, or an
  /// indicator such as a folder's chevron: each must be [FileRowAction.extent]
  /// wide, the width the row reserves per action.
  final List<Widget> actions;

  final bool isFailed;

  /// A muted line under [content]; null adds none.
  final DetailsLine? details;

  @override
  Widget build(BuildContext context) {
    final body = Row(
      children: [
        leading,
        const SizedBox(width: SoliplexSpacing.s2),
        Expanded(
          child: details == null
              ? content
              : Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      content,
                      details!,
                    ],
                  ),
                ),
        ),
      ],
    );
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: FileRowAction.extent),
      child: actions.isEmpty
          ? body
          // The entry's height comes from its text, which the actions then
          // span: laid out beside the text, they would keep their own
          // height and leave a band above and below that taps the entry.
          : Stack(
              alignment: AlignmentDirectional.centerStart,
              children: [
                Padding(
                  padding: EdgeInsetsDirectional.only(
                    end: actions.length * FileRowAction.extent,
                  ),
                  child: body,
                ),
                PositionedDirectional(
                  top: 0,
                  bottom: 0,
                  end: 0,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: actions,
                  ),
                ),
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

/// The muted second line of a [FileListRow], such as a file's `5m ago ·
/// 2.4 KB` or a folder's `6 files · 2d ago`. A screen reader hears [spoken]
/// in its place, and [tooltip], when given, shows on hover or, on touch, a
/// long press.
class DetailsLine extends StatelessWidget {
  const DetailsLine({
    super.key,
    required this.text,
    required this.spoken,
    this.tooltip,
  });

  /// A file's modified time, relative, and its size, each left out when
  /// unknown, with the exact local time in the tooltip; null when both are
  /// unknown.
  static DetailsLine? file({DateTime? modifiedAt, int? sizeBytes}) {
    if (modifiedAt == null && sizeBytes == null) return null;
    return DetailsLine(
      text: [
        if (modifiedAt != null) formatRelativeTime(modifiedAt),
        if (sizeBytes != null) formatFileSize(sizeBytes),
      ].join(' · '),
      spoken: [
        if (modifiedAt != null) 'modified ${spokenRelativeTime(modifiedAt)}',
        if (sizeBytes != null) spokenFileSize(sizeBytes),
      ].join(', '),
      tooltip:
          modifiedAt == null ? null : formatDateAndTime(modifiedAt.toLocal()),
    );
  }

  final String text;
  final String spoken;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tooltip = this.tooltip;
    Widget line = Semantics(
      label: spoken,
      excludeSemantics: true,
      child: Text(
        text,
        // Tighter than the theme's, so the second line sits close to the
        // name it describes.
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.3,
        ),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );
    if (tooltip != null) {
      line = Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: line,
      );
    }
    return SelectionContainer.disabled(child: line);
  }
}

/// A trailing action of a [FileListRow]: a small icon in a touch target one
/// [extent] wide that spans the row's height, named once to a screen reader.
/// Neighbouring targets touch; their padding keeps the icons apart.
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

  /// The width of every action, and the least height of a row.
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
            // Keeps the icon its own size when the row stretches the
            // target taller than one line.
            child: Center(
              child: Icon(
                icon,
                size: _iconSize,
                color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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
