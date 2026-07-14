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

/// Coordinates the two async inputs hydration needs — the room's document
/// corpus and the thread's stored filter — and resolves the selection once per
/// thread, whichever arrives last. The corpus is room-scoped; the hydrator is
/// recreated on room change (so there is no cross-room state to invalidate).
/// [setFilter] carries the thread id so a resolution can be attributed to the
/// thread it is for, and switching threads re-arms resolution.
class DocumentFilterHydrator {
  DocumentFilterHydrator({required this.onResolved});

  /// Fired once per thread with the thread id and its resolved selection. The
  /// caller applies it only if that thread is still active and the user has not
  /// edited the selection (local edit wins).
  final void Function(String threadId, Set<RagDocument> selection) onResolved;

  Map<String, RagDocument> _corpusById = const {};
  bool _hasCorpus = false;
  String? _threadId;
  String? _filter;
  bool _hasFilter = false;
  bool _resolved = false;

  /// Room-scoped corpus.
  void setCorpus(List<RagDocument> corpus) {
    _corpusById = {for (final doc in corpus) doc.id: doc};
    _hasCorpus = true;
    _tryResolve();
  }

  /// The thread's last-run filter (may be null = unfiltered). Switching to a new
  /// thread re-arms resolution for it.
  void setFilter(String threadId, String? filter) {
    if (threadId != _threadId) {
      _threadId = threadId;
      _resolved = false;
    }
    _filter = filter;
    _hasFilter = true;
    _tryResolve();
  }

  void _tryResolve() {
    final threadId = _threadId;
    if (_resolved || !_hasCorpus || !_hasFilter || threadId == null) return;
    _resolved = true;
    onResolved(threadId, resolveSelectionFromFilter(_filter, _corpusById));
  }
}
