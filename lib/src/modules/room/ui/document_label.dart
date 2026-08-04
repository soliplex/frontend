import 'package:flutter/material.dart';

/// A document's [name], over the documents containing it when it is embedded in
/// one — `in annual-report.pdf`, chaining to `in contract.pdf > exhibit-a.pdf`
/// when it is embedded two deep.
///
/// Each line is capped at one, so a document occupies one line when it is plain
/// and two when it is embedded, whatever its names run to. Both a citation list
/// and a document listing put many of these in a scrolling column, and document
/// filenames are routinely long enough to wrap, so letting them do so would size
/// every row by whichever name happened to be longest.
///
/// One tooltip covers both lines, because the same cap cuts both. It carries the
/// two names as a sentence rather than a stack, so what a reader recovers states
/// the relationship instead of implying it from an arrangement they can no longer
/// see.
class DocumentLabel extends StatelessWidget {
  const DocumentLabel({
    required this.name,
    required this.ancestorNames,
    this.style,
    super.key,
  });

  /// The name this document is labelled with.
  final String name;

  /// The documents containing it, outermost first. Empty when it is not
  /// embedded in one, which renders the name alone.
  final List<String> ancestorNames;

  /// The [name]'s text style, and only its own — the provenance line is always
  /// secondary to whatever the name is set in. Null inherits the surrounding
  /// default, which is what a [ListTile] title slot wants.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provenance =
        ancestorNames.isEmpty ? null : 'in ${ancestorNames.join(' > ')}';

    return Tooltip(
      message: ancestorNames.isEmpty
          ? name
          : '$name embedded in ${ancestorNames.join(' > ')}',
      waitDuration: const Duration(milliseconds: 500),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (provenance != null)
            Text(
              provenance,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}
