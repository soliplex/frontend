import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/copy_button.dart';
import 'markdown/flutter_markdown_plus_renderer.dart';

class CitationsSection extends StatefulWidget {
  const CitationsSection({
    super.key,
    required this.sourceReferences,
    this.onShowChunkVisualization,
  });

  final List<SourceReference> sourceReferences;
  final void Function(SourceReference)? onShowChunkVisualization;

  @override
  State<CitationsSection> createState() => _CitationsSectionState();
}

class _CitationsSectionState extends State<CitationsSection> {
  bool _sectionExpanded = false;
  final Set<int> _expandedIndices = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = widget.sourceReferences.length;

    return Column(
      crossAxisAlignment: .start,
      children: [
        const SizedBox(height: 8),
        Row(
          mainAxisSize: .min,
          children: [
            InkWell(
              onTap: () => setState(() => _sectionExpanded = !_sectionExpanded),
              borderRadius: .circular(8),
              child: Padding(
                padding: const .symmetric(vertical: 4, horizontal: 4),
                child: Row(
                  mainAxisSize: .min,
                  children: [
                    Transform.flip(
                      flipX: true,
                      child: Icon(
                        Icons.format_quote,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$count source${count == 1 ? '' : 's'}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      _sectionExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (count > 0)
              SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: CopyButton(
                    icon: Icons.copy_all,
                    iconSize: 16,
                    tooltip: 'Copy all',
                    text: formatAllCitationsForClipboard(
                      widget.sourceReferences,
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (_sectionExpanded) ...[
          const SizedBox(height: 4),
          ...List.generate(widget.sourceReferences.length, (index) {
            final ref = widget.sourceReferences[index];
            return _SourceReferenceRow(
              sourceReference: ref,
              badgeNumber: ref.index ?? (index + 1),
              isExpanded: _expandedIndices.contains(index),
              onToggle: () => setState(() {
                if (_expandedIndices.contains(index)) {
                  _expandedIndices.remove(index);
                } else {
                  _expandedIndices.add(index);
                }
              }),
              onShowChunkVisualization: widget.onShowChunkVisualization,
            );
          }),
        ],
      ],
    );
  }
}

class _SourceReferenceRow extends StatelessWidget {
  const _SourceReferenceRow({
    required this.sourceReference,
    required this.badgeNumber,
    required this.isExpanded,
    required this.onToggle,
    this.onShowChunkVisualization,
  });

  final SourceReference sourceReference;
  final int badgeNumber;
  final bool isExpanded;
  final VoidCallback onToggle;
  final void Function(SourceReference)? onShowChunkVisualization;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const .only(bottom: 4),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onToggle,
                  borderRadius: .circular(8),
                  child: Padding(
                    padding: const .symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: .circular(6),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$badgeNumber',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: .bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            sourceReference.displayTitle,
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: .ellipsis,
                          ),
                        ),
                        if (sourceReference.formattedPageNumbers != null) ...[
                          const SizedBox(width: 4),
                          Text(
                            sourceReference.formattedPageNumbers!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: CopyButton(
                    text: formatCitationForClipboard(sourceReference),
                    tooltip: 'Copy citation $badgeNumber',
                    iconSize: 16,
                  ),
                ),
              ),
              InkWell(
                onTap: onToggle,
                borderRadius: .circular(8),
                child: Padding(
                  padding: const .all(8),
                  child: Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (isExpanded) _buildExpandedContent(context, theme),
        ],
      ),
    );
  }

  Widget _buildExpandedContent(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const .only(left: 32, bottom: 8),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          if (sourceReference.headings.isNotEmpty)
            Padding(
              padding: const .only(bottom: 4),
              child: Text(
                sourceReference.headings.join(' > '),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: .ellipsis,
              ),
            ),
          if (sourceReference.content.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 250),
              padding: const .all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: .circular(12),
              ),
              child: SingleChildScrollView(
                child: FlutterMarkdownPlusRenderer(
                  data: sourceReference.content,
                  onLinkTap: (href, _) {
                    final uri = Uri.tryParse(href);
                    if (uri != null) launchUrl(uri);
                  },
                ),
              ),
            ),
          if (sourceReference.documentUri.isNotEmpty)
            Padding(
              padding: const .only(top: 4),
              child: Text(
                sourceReference.documentUri,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: .ellipsis,
              ),
            ),
          if (sourceReference.isPdf && onShowChunkVisualization != null)
            Padding(
              padding: const .only(top: 4),
              child: TextButton.icon(
                onPressed: () => onShowChunkVisualization!(sourceReference),
                icon: const Icon(Icons.picture_as_pdf, size: 16),
                label: const Text('View in PDF'),
                style: TextButton.styleFrom(
                  padding: const .symmetric(horizontal: 8),
                  minimumSize: .zero,
                  tapTargetSize: .shrinkWrap,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

@visibleForTesting
String formatCitationForClipboard(SourceReference ref) {
  final lines = [ref.displayTitle];
  if (ref.headings.isNotEmpty) {
    lines.add(ref.headings.join(' > '));
  }
  final pages = ref.formattedPageNumbers;
  if (pages != null) {
    lines.add(pages);
  }
  if (ref.documentUri.isNotEmpty) {
    lines.add(ref.documentUri);
  }
  if (ref.content.isNotEmpty) {
    lines
      ..add('')
      ..add(ref.content);
  }
  return lines.join('\n');
}

@visibleForTesting
String formatAllCitationsForClipboard(List<SourceReference> refs) =>
    refs.map(formatCitationForClipboard).join('\n\n---\n\n');
