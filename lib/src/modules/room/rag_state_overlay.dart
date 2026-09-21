import 'package:soliplex_client/soliplex_client.dart'
    show
        RagDatabaseScope,
        RagDocument,
        buildDocumentFilter,
        buildRagDocumentFilterOverlay,
        buildRagSourcesOverlay;

/// The AG-UI state overlay a send asserts for a thread's RAG scope: the
/// document filter, when filtering is enabled, and the database selection,
/// when the room offers one. Null when neither applies, so the send carries
/// the thread's cached state untouched.
///
/// The two are merged per namespace: `rag` may carry both keys, while a
/// namespace only the selection reaches (`analysis`) carries `sources` alone.
///
/// The selection is sent whenever there is a choice, made or not: the `null`
/// for "every database" is what clears a narrower `sources` the thread's
/// cached state may still carry from an earlier turn. Each namespace is sent
/// only the names it searches, in the manifest's order: a name it does not
/// list — hydrated from an older run for a database since dropped, or listed
/// by the room's other skill — would fail the run. A namespace none of the
/// selection reaches is sent `null`, every database it has, rather than a
/// list of none.
Map<String, dynamic>? buildRagStateOverlay({
  required bool filterEnabled,
  required Set<RagDocument> selectedDocuments,
  required RagDatabaseScope scope,
  required Set<String> selectedDatabases,
}) {
  final overlay = <String, dynamic>{};
  if (filterEnabled) {
    overlay.addAll(
      buildRagDocumentFilterOverlay(
        selectedDocuments.isEmpty
            ? null
            : buildDocumentFilter(selectedDocuments.toList()),
      ),
    );
  }
  if (scope.isSelectable) {
    for (final namespace in scope.namespaces) {
      final names =
          scope.namesFor(namespace).where(selectedDatabases.contains).toList();
      final sources = buildRagSourcesOverlay(
        names.isEmpty ? null : names,
        namespaces: [namespace],
      );
      final existing = overlay[namespace];
      overlay[namespace] = <String, dynamic>{
        if (existing is Map<String, dynamic>) ...existing,
        ...sources[namespace] as Map<String, dynamic>,
      };
    }
  }
  return overlay.isEmpty ? null : overlay;
}
