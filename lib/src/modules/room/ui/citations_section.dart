import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;
import 'package:url_launcher/url_launcher.dart';

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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        InkWell(
          onTap: () => setState(() => _sectionExpanded = !_sectionExpanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
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
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$badgeNumber',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sourceReference.displayTitle,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) _buildExpandedContent(context, theme),
        ],
      ),
    );
  }

  Widget _buildExpandedContent(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(left: 32, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sourceReference.headings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                sourceReference.headings.join(' > '),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (sourceReference.content.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 250),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
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
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                sourceReference.documentUri,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (sourceReference.isPdf && onShowChunkVisualization != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: TextButton.icon(
                onPressed: () => onShowChunkVisualization!(sourceReference),
                icon: const Icon(Icons.picture_as_pdf, size: 16),
                label: const Text('View in PDF'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
