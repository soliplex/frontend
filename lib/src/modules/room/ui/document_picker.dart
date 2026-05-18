import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' hide State;

import '../../../shared/file_type_icons.dart';
import '../../../../soliplex_frontend.dart';

class DocumentPicker extends StatefulWidget {
  const DocumentPicker({
    super.key,
    required this.documents,
    required this.selected,
    required this.onChanged,
    this.onSearchChanged,
  });

  final List<RagDocument> documents;
  final Set<RagDocument> selected;
  final ValueChanged<Set<RagDocument>> onChanged;
  final ValueChanged<int>? onSearchChanged;

  @override
  State<DocumentPicker> createState() => _DocumentPickerState();
}

class _DocumentPickerState extends State<DocumentPicker> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<RagDocument> get _filtered => filterDocuments(widget.documents, _query);

  void _toggle(RagDocument doc) {
    final next = Set<RagDocument>.of(widget.selected);
    if (!next.remove(doc)) next.add(doc);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filtered;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search documents...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: 'Clear search',
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                          _query = '';
                        });
                        widget.onSearchChanged?.call(_filtered.length);
                      },
                    )
                  : null,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) {
              setState(() => _query = v);
              widget.onSearchChanged?.call(_filtered.length);
            },
          ),
        ),
        if (widget.selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${widget.selected.length} selected',
                  style: theme.textTheme.bodySmall,
                ),
                TextButton(
                  onPressed: () => widget.onChanged(const {}),
                  child: const Text('Clear all'),
                ),
              ],
            ),
          ),
        Flexible(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'No documents found',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final doc = filtered[index];
                    final selected = widget.selected.contains(doc);
                    return CheckboxListTile(
                      secondary: Icon(getFileTypeIcon(documentIconPath(doc))),
                      title: Text(
                        documentDisplayName(doc),
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: doc.uri.isNotEmpty
                          ? Text(
                              doc.uri,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            )
                          : null,
                      value: selected,
                      onChanged: (_) => _toggle(doc),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Shows a document picker dialog and returns the updated selection.
///
/// Accepts a [fetchDocuments] factory so the dialog can show a loading state
/// and retry on failure.
///
/// Returns `null` if the dialog is dismissed without confirming.
Future<Set<RagDocument>?> showDocumentPicker({
  required BuildContext context,
  required Future<List<RagDocument>> Function() fetchDocuments,
  required Set<RagDocument> selected,
}) {
  var current = Set<RagDocument>.of(selected);
  int? filteredCount;
  var documentsFuture = fetchDocuments();
  return showDialog<Set<RagDocument>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => FutureBuilder<List<RagDocument>>(
        future: documentsFuture,
        builder: (context, snapshot) {
          final docs = snapshot.data;
          final String title;
          if (docs == null) {
            title = 'Select documents';
          } else {
            final filtered = filteredCount ?? docs.length;
            title = filtered == docs.length
                ? 'Select documents (${docs.length})'
                : 'Select documents ($filtered / ${docs.length})';
          }

          final Widget content;
          final bool canConfirm;
          if (snapshot.connectionState == ConnectionState.waiting) {
            canConfirm = false;
            content = const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            );
          } else if (snapshot.hasError) {
            canConfirm = false;
            developer.log(
              'Failed to load documents',
              error: snapshot.error,
              stackTrace: snapshot.stackTrace,
            );
            content = Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Failed to load documents.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                  const SizedBox(height: SoliplexSpacing.s2),
                  TextButton.icon(
                    onPressed: () => setDialogState(() {
                      documentsFuture = fetchDocuments();
                    }),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            );
          } else if (docs == null || docs.isEmpty) {
            canConfirm = true;
            content = Center(
              child: Text(
                'No documents in this room.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            );
          } else {
            canConfirm = true;
            content = DocumentPicker(
              documents: docs,
              selected: current,
              onChanged: (s) => setDialogState(() => current = s),
              onSearchChanged: (count) =>
                  setDialogState(() => filteredCount = count),
            );
          }

          return AlertDialog(
            title: Text(title),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: SizedBox(width: double.maxFinite, child: content),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    canConfirm ? () => Navigator.pop(context, current) : null,
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    ),
  );
}
