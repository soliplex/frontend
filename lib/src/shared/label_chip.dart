import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' show ThreadLabel;
import 'package:soliplex_design/soliplex_design.dart';

/// The colour to paint [label] with.
///
/// Falls back to a tint hashed from the name when the stored swatch does
/// not parse — a label with an unreadable colour is still a usable label,
/// and a blank chip would look like a rendering fault.
Color labelColor(ThreadLabel label, Brightness brightness) =>
    colorFromHex(label.color) ?? hashedHueColor(label.name, brightness);

/// A chip for one label, in the label's own colour.
class LabelChip extends StatelessWidget {
  const LabelChip({super.key, required this.label, this.onDeleted});

  final ThreadLabel label;

  /// Shows a trailing close button when non-null.
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    return SoliplexChip.colored(
      label: Text(label.name),
      color: labelColor(label, Theme.of(context).brightness),
      onDeleted: onDeleted,
    );
  }
}

/// A thread's labels on one line under its row: the first [maxShown]
/// as compact chips, then "+N" for the rest.
///
/// Kept to a single line so a labelled row stays close to the height of
/// an unlabelled one: a list of threads is for finding one, and chips
/// wrapping onto further lines would push the threads apart. The full
/// set is in the thread's properties.
///
/// Read out as one sentence ("Labels: Manuals, Urgent") rather than one
/// stop per chip, since nothing here can be pressed.
class ThreadLabelStrip extends StatelessWidget {
  const ThreadLabelStrip({super.key, required this.labels, this.maxShown = 3});

  final List<ThreadLabel> labels;

  /// How many chips to draw before folding the rest into "+N".
  final int maxShown;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final shown = labels.take(maxShown).toList(growable: false);
    final hidden = labels.length - shown.length;

    return Semantics(
      label: 'Labels: ${labels.map((l) => l.name).join(', ')}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: SoliplexSpacing.s1),
        child: Row(
          children: [
            for (final label in shown)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(right: SoliplexSpacing.s1),
                  child: SoliplexChip.colored(
                    label: Text(
                      label.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    color: labelColor(label, theme.brightness),
                    isCompact: true,
                  ),
                ),
              ),
            if (hidden > 0)
              Text(
                '+$hidden',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
