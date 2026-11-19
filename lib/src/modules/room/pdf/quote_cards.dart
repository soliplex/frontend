import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'pdf_quote.dart';

/// The quotes waiting above the composer, one removable chip each.
class QuoteChipRow extends StatelessWidget {
  const QuoteChipRow({
    super.key,
    required this.quotes,
    required this.onRemoved,
    this.onTap,
  });

  final List<PdfQuote> quotes;
  final void Function(PdfQuote quote)? onRemoved;

  /// Reopens the PDF at the quote's page. Null leaves the chips inert.
  final void Function(PdfQuote quote)? onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: SoliplexSpacing.s1),
        child: Wrap(
          spacing: SoliplexSpacing.s2,
          runSpacing: SoliplexSpacing.s2,
          children: [
            for (final quote in quotes)
              QuoteCard(
                quote: quote,
                onTap: onTap == null ? null : () => onTap!(quote),
                onRemoved: onRemoved == null ? null : () => onRemoved!(quote),
              ),
          ],
        ),
      );
}

/// One quoted passage: an excerpt, then the page and file it came from.
///
/// A removable chip above the composer when [onRemoved] is set; a card in a
/// sent message when it is not. Either way it sits on its own surface, so it
/// reads the same on the composer's background and in the user's bubble.
class QuoteCard extends StatelessWidget {
  const QuoteCard({
    super.key,
    required this.quote,
    this.onTap,
    this.onRemoved,
    this.maxWidth = 320,
    this.excerptLength = 60,
  });

  final PdfQuote quote;
  final VoidCallback? onTap;
  final VoidCallback? onRemoved;
  final double maxWidth;
  final int excerptLength;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final where = 'p. ${quote.pageNumber} · ${quote.documentTitle}';
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Semantics(
        label: 'Quote from ${quote.documentTitle}, page ${quote.pageNumber}',
        button: onTap != null,
        child: Material(
          color: scheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.radii.md),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                SoliplexSpacing.s2,
                SoliplexSpacing.s2,
                onRemoved == null ? SoliplexSpacing.s3 : 0,
                SoliplexSpacing.s2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      Icons.format_quote,
                      size: 18,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: SoliplexSpacing.s2),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '“${quote.excerpt(excerptLength)}”',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          where,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (onRemoved case final remove?)
                    IconButton(
                      tooltip: 'Remove quote',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      icon: const Icon(Icons.close),
                      onPressed: remove,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
