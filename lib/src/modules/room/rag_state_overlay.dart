import 'package:soliplex_client/soliplex_client.dart'
    show
        RagDatabaseScope,
        RagDocument,
        buildDocumentFilter,
        buildRagDocumentFilterOverlay,
        buildRagSourcesOverlay;

/// The AG-UI state overlay a send asserts for a thread's RAG scope: the
/// document filter, when filtering is enabled, and the database selection,
/// when the room offers one or [clearsNarrowedSources] says the thread needs
/// one cleared. Null when none applies, so the send carries the thread's
/// cached state untouched.
///
/// The two are merged per namespace: `rag` may carry both keys, while a
/// namespace only the selection reaches (`analysis`) carries `sources` alone.
///
/// The selection is sent whenever there is a choice, made or not: the `null`
/// for "every database" is what clears a narrower `sources` the thread's
/// cached state may still carry from an earlier turn. A room with no choice
/// is sent nothing, unless [clearsNarrowedSources]: a thread narrowed while
/// its room offered a choice carries that `sources` after the room drops to
/// one database, and a name the room no longer lists fails every run until
/// the `null` overwrites it. Each namespace is sent
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
  required bool clearsNarrowedSources,
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
  if (scope.isSelectable || clearsNarrowedSources) {
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

/// The part of a thread's [stored] selection the room still lists. Empty means
/// every database — the backend's default — which a selection covering all of
/// them also reads as, so a history that listed every database shows and sends
/// the same as a user who selected them all. A name hydrated from an older run,
/// for a database since dropped from the room, would fail the run if sent.
Set<String> selectedDatabasesIn(Set<String> stored, RagDatabaseScope scope) {
  final known = stored.where(scope.names.contains).toSet();
  return known.length == scope.names.length ? const {} : known;
}

/// The selection after toggling [name] in [current] (as [selectedDatabasesIn]
/// reads it), or null for a tap that is refused: the last selected database
/// cannot be deselected, since an empty selection would read as "every
/// database", lighting all of them back up under the tap that cleared the last
/// one. A selection that covers every database comes back as the default.
Set<String>? toggledDatabases(
  RagDatabaseScope scope,
  Set<String> current,
  String name, {
  required bool selected,
}) {
  final next = {...(current.isEmpty ? scope.names : current)};
  if (selected) {
    next.add(name);
  } else {
    if (next.length <= 1) return null;
    next.remove(name);
  }
  return next.length == scope.names.length ? const {} : next;
}
