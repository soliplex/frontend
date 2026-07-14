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
/// corpus and the thread's stored filter — and resolves the selection exactly
/// once per thread, whichever input arrives last. The corpus is room-scoped
/// and survives thread switches; [beginThread] resets the per-thread filter
/// state so the next thread re-resolves.
class DocumentFilterHydrator {
  DocumentFilterHydrator({required this.onResolved});

  /// Fired once per thread with the resolved selection. The caller decides
  /// whether to apply it (e.g. skip if the user already edited the selection).
  final void Function(Set<RagDocument> selection) onResolved;

  Map<String, RagDocument> _corpusById = const {};
  bool _hasCorpus = false;
  String? _filter;
  bool _hasFilter = false;
  bool _resolved = false;

  /// Room-scoped corpus; survives [beginThread].
  void setCorpus(List<RagDocument> corpus) {
    _corpusById = {for (final doc in corpus) doc.id: doc};
    _hasCorpus = true;
    _tryResolve();
  }

  /// Resets per-thread filter state on thread (re)open; keeps the corpus.
  void beginThread() {
    _filter = null;
    _hasFilter = false;
    _resolved = false;
  }

  /// The thread's last-run filter (may be null = unfiltered).
  void setFilter(String? filter) {
    _filter = filter;
    _hasFilter = true;
    _tryResolve();
  }

  void _tryResolve() {
    if (_resolved || !_hasCorpus || !_hasFilter) return;
    _resolved = true;
    onResolved(resolveSelectionFromFilter(_filter, _corpusById));
  }
}
