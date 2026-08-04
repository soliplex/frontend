import 'package:flutter/material.dart';

/// Names a document and the documents containing it in one sentence —
/// `budget.xlsx embedded in annual-report.pdf`, chaining through each level when
/// it is embedded two deep, and the name alone when it is embedded in nothing.
///
/// Spelled as a sentence rather than stacked the way [DocumentLabel] renders it,
/// so a reader recovering a truncated row is told the relationship instead of
/// having to read it off an arrangement. Shared so that every surface naming an
/// embedded file says it the same way, whether it has room for a second line or
/// only a tooltip.
String documentProvenanceSentence(String name, List<String> ancestorNames) =>
    ancestorNames.isEmpty
        ? name
        : '$name embedded in ${ancestorNames.join(' > ')}';

/// A document's [name], over the documents containing it when it is embedded in
/// one — `in annual-report.pdf`, chaining to `in contract.pdf > exhibit-a.pdf`
/// when it is embedded two deep.
///
/// Each line is capped at one, so a document occupies one line when it is plain
/// and two when it is embedded, whatever its names run to. Document filenames are
/// routinely long enough to wrap, and these sit in columns of many rows — a
/// citation list, two document listings — where a row growing to fit its own name
/// makes the height of every row depend on what it happens to be called.
///
/// One tooltip covers both lines, because the same cap cuts both.
class DocumentLabel extends StatelessWidget {
  const DocumentLabel({
    required this.name,
    required this.ancestorNames,
    this.style,
    super.key,
  }) : assert(name != '', 'a label needs a name to render');

  /// The name this document is labelled with.
  ///
  /// A name that reads blank renders an invisible line and a blank tooltip, so
  /// each caller resolves an absent name to a label of its own — a document
  /// listing to `Untitled`, a citation to `Unknown Document` — before passing
  /// it here.
  final String name;

  /// The documents containing it, outermost first. Empty when it is not
  /// embedded in one, which renders the name alone.
  final List<String> ancestorNames;

  /// The [name]'s text style. The provenance line keeps its own, secondary
  /// whatever the name is set in. Null inherits the surrounding default, which
  /// is what a [ListTile] title slot wants.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provenance =
        ancestorNames.isEmpty ? null : 'in ${ancestorNames.join(' > ')}';

    return Tooltip(
      message: documentProvenanceSentence(name, ancestorNames),
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
