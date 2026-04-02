import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' hide State;

import '../../../../shared/file_type_icons.dart';
import 'room_info_widgets.dart';

class DocumentsCard extends StatefulWidget {
  const DocumentsCard({
    super.key,
    required this.documentsFuture,
    required this.onRetry,
  });

  final Future<List<RagDocument>> documentsFuture;
  final VoidCallback onRetry;

  @override
  State<DocumentsCard> createState() => _DocumentsCardState();
}

class _DocumentsCardState extends State<DocumentsCard> {
  static const _maxHeight = 550.0;
  static const _shrinkWrapThreshold = 50;

  final _expandedIds = <String>{};
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RagDocument> _filterDocs(List<RagDocument> docs) {
    if (_searchQuery.isEmpty) return docs;
    final query = _searchQuery.toLowerCase();
    return docs
        .where(
          (d) => documentDisplayName(d).toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<List<RagDocument>>(
      future: widget.documentsFuture,
      builder: (context, snapshot) {
        final String title;
        final List<Widget> children;

        if (snapshot.connectionState == ConnectionState.waiting) {
          title = 'DOCUMENTS';
          children = [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ];
        } else if (snapshot.hasError) {
          title = 'DOCUMENTS';
          children = [
            Row(
              children: [
                Icon(
                  Icons.error_outline,
                  size: 18,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Failed to load documents',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
                FilledButton(
                  onPressed: widget.onRetry,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ];
        } else {
          final docs = snapshot.data ?? const [];
          if (docs.isEmpty) {
            title = 'DOCUMENTS (0)';
            children = [
              Text(
                'No documents in this room.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ];
          } else {
            final filtered = _filterDocs(docs);
            title = _searchQuery.isEmpty
                ? 'DOCUMENTS (${docs.length})'
                : 'DOCUMENTS (${filtered.length} / ${docs.length})';
            children = [
              if (docs.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search documents...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              tooltip: 'Clear search',
                              onPressed: () => setState(() {
                                _searchController.clear();
                                _searchQuery = '';
                              }),
                            )
                          : null,
                      isDense: true,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: _maxHeight),
                child: ListView.builder(
                  shrinkWrap: filtered.length <= _shrinkWrapThreshold,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final doc = filtered[index];
                    final expanded = _expandedIds.contains(doc.id);
                    return _buildDocTile(doc, expanded, theme);
                  },
                ),
              ),
            ];
          }
        }

        return SectionCard(
          title: title,
          children: children,
        );
      },
    );
  }

  Widget _buildDocTile(
    RagDocument doc,
    bool expanded,
    ThemeData theme,
  ) {
    return GestureDetector(
      onTap: () => setState(() {
        if (expanded) {
          _expandedIds.remove(doc.id);
        } else {
          _expandedIds.add(doc.id);
        }
      }),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  getFileTypeIcon(documentIconPath(doc)),
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    documentDisplayName(doc),
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            if (expanded) _buildDocMetadata(doc),
          ],
        ),
      ),
    );
  }

  Widget _buildDocMetadata(RagDocument doc) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurfaceVariant,
    );
    final valueStyle = theme.textTheme.bodySmall;

    final dateFields = <(String, String)>[];
    if (doc.createdAt != null) {
      dateFields.add(('created_at', _formatDateTime(doc.createdAt!)));
    }
    if (doc.updatedAt != null) {
      dateFields.add(('updated_at', _formatDateTime(doc.updatedAt!)));
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('id', style: labelStyle),
            const SizedBox(height: 2),
            SelectableText(
              doc.id,
              style: valueStyle?.copyWith(fontFamily: 'monospace'),
            ),
            if (doc.uri.isNotEmpty || dateFields.isNotEmpty)
              const SizedBox(height: 8),
            if (doc.uri.isNotEmpty) ...[
              Text('uri', style: labelStyle),
              const SizedBox(height: 2),
              SelectableText(
                doc.uri,
                style: valueStyle?.copyWith(fontFamily: 'monospace'),
              ),
              if (dateFields.isNotEmpty) const SizedBox(height: 8),
            ],
            if (dateFields.isNotEmpty)
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  for (final (label, value) in dateFields)
                    SizedBox(
                      width: 160,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label, style: labelStyle),
                          const SizedBox(height: 2),
                          SelectableText(
                            value,
                            style: valueStyle,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            if (doc.metadata.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  style: TextButton.styleFrom(
                    textStyle: theme.textTheme.labelSmall,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => MetadataDialog(
                      title: doc.title,
                      metadata: doc.metadata,
                    ),
                  ),
                  child: const Text('Show metadata'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

class MetadataDialog extends StatelessWidget {
  const MetadataDialog({
    super.key,
    required this.title,
    required this.metadata,
  });

  final String title;
  final Map<String, dynamic> metadata;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final entries = metadata.entries.toList();

    return AlertDialog(
      title: Text(
        title,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in entries) ...[
                SizedBox(
                  width: double.infinity,
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          formatDynamicValue(
                            entry.value,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (entry.key != entries.last.key) const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
