import 'package:ag_ui/ag_ui.dart';
import 'package:soliplex_client/src/application/rag_snapshot.dart';
import 'package:soliplex_client/src/domain/source_reference.dart';
import 'package:soliplex_client/src/schema/agui_features/rag.dart';
import 'package:soliplex_client/src/utils/source_url.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final _logger =
    LogManager.instance.getLogger('soliplex_client.citation_extractor');

/// Reads and resolves citations from AG-UI state snapshots.
///
/// **Schema firewall**: this file and [RagSnapshot] in
/// `rag_snapshot.dart` are the only places that import the schema-mirror
/// types in `rag.dart`. When the backend citation shape changes, updates
/// are confined to `rag_snapshot.dart`.
///
/// Each RAG-producing skill (`rag`, `analysis`, …) publishes its own
/// citation-bearing namespace. [citationIdsInDelta] collects the ids a single
/// `StateDeltaEvent` cited; [resolve] turns a set of ids into full
/// [SourceReference]s using the state's session-cumulative `citation_index`.
/// Neither subtracts a prior turn's ids — accumulation across a turn is the
/// caller's responsibility.
class CitationExtractor {
  /// The union of chunk ids cited in [state], restricted to [namespaces] when
  /// given, else across every citation-bearing namespace.
  ///
  /// The backend clears a namespace's `citations` list only when that skill is
  /// invoked, so an untouched namespace's list is a prior turn's. Prefer
  /// [citationIdsInDelta] during accumulation, which scopes to the namespaces a
  /// delta actually touched.
  Set<String> citationIds(
    Map<String, dynamic> state, {
    Set<String>? namespaces,
  }) {
    return <String>{
      for (final snapshot
          in RagSnapshot.extractAll(state, namespaces: namespaces))
        ...snapshot.citationIds,
    };
  }

  /// The union of chunk ids cited in the namespaces that [delta] modified.
  ///
  /// The backend re-emits every namespace's block in `state` — including a
  /// prior turn's untouched one, whose stale `citations` ride the run's rebase
  /// snapshot — but clears and repopulates `citations` only in the invoked
  /// skill's namespace. So a namespace this delta did not touch carries a prior
  /// turn's ids and must not be attributed to this one. Scoping to the
  /// delta's touched namespaces is what keeps re-cited chunks and
  /// multi-invocation runs while not inventing a stale namespace's citations.
  Set<String> citationIdsInDelta(
    Map<String, dynamic> state,
    StateDeltaEvent delta,
  ) {
    final namespaces = _touchedNamespaces(delta);
    if (namespaces.isEmpty) return const <String>{};
    return citationIds(state, namespaces: namespaces);
  }

  /// The top-level state keys touched by [delta]'s JSON-Patch ops, e.g.
  /// `/rag/citations/-` → `rag`. A malformed op is skipped with a warning:
  /// silently dropping it could lose a namespace's citations off a drifting
  /// wire with no trace.
  Set<String> _touchedNamespaces(StateDeltaEvent delta) {
    final namespaces = <String>{};
    for (final op in delta.delta) {
      if (op is! Map) {
        _logger.warning('citationIdsInDelta: skipping non-Map delta op: $op');
        continue;
      }
      final path = op['path'];
      if (path is! String) {
        _logger.warning(
          'citationIdsInDelta: skipping delta op with non-String path: $op',
        );
        continue;
      }
      final segments = path.split('/').where((s) => s.isNotEmpty);
      if (segments.isEmpty) {
        _logger.warning(
          'citationIdsInDelta: skipping delta op with no namespace segment '
          'in path: $op',
        );
        continue;
      }
      namespaces.add(segments.first);
    }
    return namespaces;
  }

  /// Resolves [ids] to full [SourceReference]s against the citation index in
  /// [state], deduping ids and logging then omitting any absent from every
  /// namespace's index — an absent cited id signals a backend contract
  /// violation (the index is cumulative), so it is surfaced, not dropped
  /// silently.
  ///
  /// Ids are looked up in `citation_index`, which is session-cumulative, so an
  /// id cited in an earlier invocation still resolves even when it is no longer
  /// in the current `citations` list. No subtraction of any kind is applied.
  ///
  /// Never throws: a namespace whose block fails to parse is skipped by
  /// [RagSnapshot.extractAll], everything after operates on already-parsed
  /// snapshots, and the one render-time decode ([RagSnapshot.pictureBytes]'s
  /// base64 decode) is itself guarded.
  List<SourceReference> resolve(
    Iterable<String> ids,
    Map<String, dynamic> state, {
    String? logContext,
  }) {
    final snapshots = RagSnapshot.extractAll(state);

    final refs = <SourceReference>[];
    final seen = <String>{};
    final unresolved = <String>[];
    for (final id in ids) {
      if (!seen.add(id)) continue;
      var resolved = false;
      for (final snapshot in snapshots) {
        final citation = snapshot.resolveCitation(id);
        if (citation != null) {
          refs.add(_citationToSourceReference(citation, snapshot));
          resolved = true;
          break;
        }
      }
      if (!resolved) unresolved.add(id);
    }
    // A cited id absent from every `citation_index` means the rendered source
    // list is silently short — a backend contract violation, since the index is
    // cumulative. Surface it rather than dropping it without a trace.
    if (unresolved.isNotEmpty) {
      final where = logContext != null ? ' [$logContext]' : '';
      _logger.warning(
        'resolve$where: ${unresolved.length} cited id(s) absent from every '
        'citation_index; source list rendered incomplete. ids: $unresolved',
      );
    }
    return refs;
  }

  SourceReference _citationToSourceReference(Citation c, RagSnapshot rag) {
    final figures = <Figure>[];
    for (final ref in c.pictureRefs ?? const <String>[]) {
      final bytes = rag.pictureBytes(c.documentId, ref);
      if (bytes == null) continue;
      final caption = rag.pictureCaption(c.documentId, ref);
      figures.add(
        Figure(
          ref: ref,
          bytes: bytes,
          caption: caption != null && caption.isNotEmpty ? caption : null,
        ),
      );
    }
    if (hasMalformedSourceUrl(c.documentMeta)) {
      _logger.warning(
        'Citation source_url present but not a launchable web URL '
        '(document ${c.documentId})',
      );
    }
    return SourceReference(
      documentId: c.documentId,
      documentUri: c.documentUri,
      content: c.content,
      chunkId: c.chunkId,
      documentTitle: c.documentTitle,
      sourceUrl: sourceUrlFromMetadata(c.documentMeta),
      headings: c.headings ?? [],
      pageNumbers: c.pageNumbers ?? [],
      docItemRefs: c.docItemRefs ?? [],
      figures: figures,
      chunkIds: c.chunkIds ?? [],
      index: c.index,
    );
  }
}
