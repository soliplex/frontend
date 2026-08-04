import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// One labelled fact about a document: a muted-bold [label] lead-in followed by
/// its [value] on the same line.
///
/// A null or blank [value] renders nothing, the lead-in included, so a fact the
/// document does not carry leaves no label announcing an empty value.
class DocumentMetadataLine extends StatelessWidget {
  /// A line whose value is prose — a title, a caption — capped at [maxLines].
  const DocumentMetadataLine({
    required this.label,
    required this.value,
    this.maxLines = 2,
    super.key,
  }) : _isIdentifier = false;

  /// A line whose value is an identifier — a chunk id, a document id.
  ///
  /// Monospaced, and wrapped to the margin rather than clipped: an identifier
  /// is only useful entire, so hiding its tail behind an ellipsis would leave
  /// nothing worth reading.
  const DocumentMetadataLine.identifier({
    required this.label,
    required this.value,
    super.key,
  })  : maxLines = null,
        _isIdentifier = true;

  /// The fact's name, rendered as the lead-in.
  final String label;

  /// The fact, or null when the document does not carry it.
  final String? value;

  /// How many lines the value may occupy before it ellipsizes. Null lets it
  /// wrap freely.
  final int? maxLines;

  final bool _isIdentifier;

  @override
  Widget build(BuildContext context) {
    final resolved = value?.trim();
    if (resolved == null || resolved.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: SoliplexSpacing.s1),
      child: Text.rich(
        TextSpan(
          style: labelStyle,
          children: [
            TextSpan(text: '$label  '),
            TextSpan(
              text: resolved,
              style: _isIdentifier
                  ? context.monospaceOn(
                      theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  : theme.textTheme.bodySmall,
            ),
          ],
        ),
        maxLines: maxLines,
        overflow: maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
      ),
    );
  }
}

/// A document's title, on a [DocumentMetadataLine].
///
/// A title row reads the same wherever one appears: same lead-in, same style,
/// chosen once here.
class DocumentTitleLine extends StatelessWidget {
  const DocumentTitleLine({required this.title, super.key});

  /// The document's title, or null when it has none. A caller whose title
  /// field stands in a placeholder when the backend sent none has to resolve
  /// that to null first; blank is the only absence this reads.
  final String? title;

  @override
  Widget build(BuildContext context) =>
      DocumentMetadataLine(label: 'title', value: title);
}
