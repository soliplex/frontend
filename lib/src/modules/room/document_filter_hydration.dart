import 'package:soliplex_client/soliplex_client.dart';

/// Title shown for a filtered document id that is no longer in the room's
/// corpus (deleted server-side). The id is still sent in the filter so the
/// search stays correctly scoped; the placeholder makes the deletion visible.
const String unavailableDocumentTitle = 'Unavailable document';

/// Resolves a thread's document-filter WHERE clause into the selected
/// documents, using [corpusById] (the room's current corpus keyed by id) to
/// recover titles. An id absent from the corpus becomes a placeholder
/// [RagDocument] titled [unavailableDocumentTitle] and is kept in the set, so
/// [buildDocumentFilter] still targets it (no silent scope-broadening).
///
/// A null [filter] yields an empty set (the thread is unfiltered).
Set<RagDocument> resolveSelectionFromFilter(
  String? filter,
  Map<String, RagDocument> corpusById,
) {
  if (filter == null) return {};
  return {
    for (final id in parseDocumentFilter(filter))
      corpusById[id] ?? RagDocument(id: id, title: unavailableDocumentTitle),
  };
}
