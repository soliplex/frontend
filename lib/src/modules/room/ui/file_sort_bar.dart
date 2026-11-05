import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../file_sort.dart';

/// The four ways a file list can be ordered, as one segmented row. The
/// active segment shows its direction; tapping it reports its key, as a tap
/// on any other enabled segment does, so the caller can reverse it.
///
/// Not Material's `SegmentedButton`: it gives every segment an equal width
/// and a segment with an icon fixed padding, so on a 320 px screen the active
/// label and its arrow do not fit. Here each segment takes its own width.
class FileSortBar extends StatelessWidget {
  const FileSortBar({
    super.key,
    required this.sort,
    required this.hasTimes,
    required this.hasSizes,
    required this.onTap,
  });

  /// The order the list renders, which can differ from the stored choice.
  final FileSort sort;

  /// Whether any entry has a modified time; false disables Modified.
  final bool hasTimes;

  /// Whether any entry has a size; false disables Size.
  final bool hasSizes;

  /// Called with the key of every tap on an enabled segment, active or not.
  final ValueChanged<FileSortKey> onTap;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    final radius = BorderRadius.circular(context.radii.md);
    final segments = [
      (key: FileSortKey.name, label: 'Name', unavailable: null),
      (
        key: FileSortKey.modified,
        label: 'Modified',
        unavailable:
            hasTimes ? null : 'None of these files has a modified time',
      ),
      (
        key: FileSortKey.size,
        label: 'Size',
        unavailable: hasSizes ? null : 'None of these files has a size',
      ),
      (key: FileSortKey.folders, label: 'Folders', unavailable: null),
    ];
    // Scrolls sideways when a large text scale or a wide brand font makes
    // it wider than the panel, so the labels keep the size the reader chose.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: outline),
          borderRadius: radius,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Material(
            type: MaterialType.transparency,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, s) in segments.indexed)
                  _Segment(
                    label: s.label,
                    active: s.key == sort.key,
                    descending: sort.descending,
                    description: s.unavailable ??
                        (s.key == sort.key
                            ? sort.description
                            : FileSort.firstTap(s.key).description),
                    divider: i > 0 ? outline : null,
                    onTap: s.unavailable == null ? () => onTap(s.key) : null,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.active,
    required this.descending,
    required this.description,
    required this.divider,
    required this.onTap,
  });

  final String label;
  final bool active;
  final bool descending;

  /// The tooltip: the order this segment shows or a tap would select, or why
  /// it is disabled. Also the semantics label, which for a disabled segment
  /// starts with [label], since the reason does not name the segment.
  final String description;

  /// The colour of the line on the segment's left edge; none for the first
  /// segment.
  final Color? divider;

  /// Null disables the segment.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onTap != null;
    // Material's disabled foreground: the surface's text at 38%.
    final foreground = !enabled
        ? scheme.onSurface.withValues(alpha: 0.38)
        : active
            ? scheme.onPrimary
            : scheme.onSurface;
    return Tooltip(
      message: description,
      // The label below already says it; announced twice otherwise.
      excludeFromSemantics: true,
      // Outside the Semantics, so its tap and focus reach a screen reader
      // and the keyboard; the label replaces the texts beneath.
      child: InkWell(
        onTap: onTap,
        child: Semantics(
          button: true,
          selected: active,
          enabled: enabled,
          label: enabled ? description : '$label: $description',
          excludeSemantics: true,
          child: Container(
            decoration: BoxDecoration(
              color: active ? scheme.primary : null,
              border: divider == null
                  ? null
                  : Border(left: BorderSide(color: divider!)),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: SoliplexSpacing.s2,
              vertical: SoliplexSpacing.s1,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  style:
                      theme.textTheme.labelMedium?.copyWith(color: foreground),
                ),
                if (active) ...[
                  const SizedBox(width: SoliplexSpacing.s1),
                  Icon(
                    descending ? Icons.arrow_downward : Icons.arrow_upward,
                    size: 14,
                    color: foreground,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
