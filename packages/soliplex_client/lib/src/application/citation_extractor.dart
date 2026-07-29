import 'package:ag_ui/ag_ui.dart';
import 'package:meta/meta.dart';
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
/// citation-bearing namespace. [accumulate] folds each `StateDeltaEvent`'s
/// cited ids and inline figures into a running [TurnCitations]; [resolve] turns
/// an accumulated [TurnCitations] into full [SourceReference]s using the
/// state's session-cumulative `citation_index`. No subtraction of a prior
/// turn's ids is applied — the caller owns the turn-scoped accumulator.
class CitationExtractor {
  /// The [TurnCitations] carried by [state] across every citation-bearing
  /// namespace — every cited id and every inline figure the state itself holds.
  ///
  /// This reads the whole state, so a namespace's stale `citations` (left by a
  /// prior turn and riding the rebase snapshot) is included. Use it only when
  /// [state] is a self-contained unit to resolve; during a turn's delta stream,
  /// use [accumulate], which scopes to the namespaces each delta touched.
  TurnCitations citationsInState(Map<String, dynamic> state) => _extract(state);

  /// Folds the citations and figures [delta] contributes into [current],
  /// returning the extended accumulator.
  ///
  /// Scoped to the namespaces [delta]'s JSON-Patch touched. The backend
  /// re-emits every namespace's block in `state` — including a prior turn's
  /// untouched one, whose stale `citations` ride the run's rebase snapshot —
  /// but clears and repopulates `citations` and `searches` only in the invoked
  /// skill's namespace. Scoping keeps re-cited chunks and multi-invocation runs
  /// while never crediting a namespace this delta did not invoke.
  ///
  /// Both ids and figure bytes are read from the same touched-namespace
  /// snapshots in one pass, so every accumulated id's figure (if any) is
  /// captured alongside it — even after a later invocation clears `searches`.
  TurnCitations accumulate(
    TurnCitations current,
    Map<String, dynamic> state,
    StateDeltaEvent delta,
  ) {
    final namespaces = _touchedNamespaces(delta);
    if (namespaces.isEmpty) return current;
    return current.merge(_extract(state, namespaces: namespaces));
  }

  /// One pass over [state]'s citation-bearing namespaces (all, or only
  /// [namespaces] when given), unioning each snapshot's cited ids and merging
  /// its inline figures.
  TurnCitations _extract(
    Map<String, dynamic> state, {
    Set<String>? namespaces,
  }) {
    final ids = <String>{};
    var figures = const CitedFigures.empty();
    for (final snapshot
        in RagSnapshot.extractAll(state, namespaces: namespaces)) {
      ids.addAll(snapshot.citationIds);
      figures = figures.merge(snapshot.figures);
    }
    return TurnCitations(ids, figures);
  }

  /// The top-level state keys touched by [delta]'s JSON-Patch ops, e.g.
  /// `/rag/citations/-` → `rag`. A malformed op is skipped with a warning:
  /// silently dropping it could lose a namespace's citations off a drifting
  /// wire with no trace.
  Set<String> _touchedNamespaces(StateDeltaEvent delta) {
    final namespaces = <String>{};
    for (final op in delta.delta) {
      final path = op['path'];
      if (path is! String) {
        _logger.warning(
          '_touchedNamespaces: skipping delta op with non-String path: $op',
        );
        continue;
      }
      final segments = path.split('/').where((s) => s.isNotEmpty);
      if (segments.isEmpty) {
        _logger.warning(
          '_touchedNamespaces: skipping delta op with no namespace segment '
          'in path: $op',
        );
        continue;
      }
      namespaces.add(segments.first);
    }
    return namespaces;
  }

  /// Resolves [citations] to full [SourceReference]s: each cited id's text and
  /// metadata come from the citation index in [finalState], and its inline
  /// figure bytes from [citations]'s accumulated figure union.
  ///
  /// Ids are deduped; any absent from every namespace's index is logged then
  /// omitted — an absent cited id signals a backend contract violation (the
  /// index is cumulative), so it is surfaced, not dropped silently.
  ///
  /// Ids are looked up in `citation_index`, which is session-cumulative, so an
  /// id cited in an earlier invocation still resolves even when it is no longer
  /// in the current `citations` list. Figure bytes come from
  /// [citations].figures rather than [finalState]'s `searches`, which the
  /// backend clears each invocation — the accumulated union is a superset, so
  /// this recovers figures a later invocation would otherwise have wiped. No
  /// subtraction of any kind is applied.
  ///
  /// Never throws: a namespace whose block fails to parse is skipped by
  /// [RagSnapshot.extractAll], everything after operates on already-parsed
  /// snapshots, and the one render-time decode ([CitedFigures.pictureBytes]'s
  /// base64 decode) is itself guarded.
  List<SourceReference> resolve(
    TurnCitations citations,
    Map<String, dynamic> finalState, {
    String? logContext,
  }) {
    final snapshots = RagSnapshot.extractAll(finalState);

    final refs = <SourceReference>[];
    final unresolved = <String>[];
    for (final id in citations.ids) {
      var resolved = false;
      for (final snapshot in snapshots) {
        final citation = snapshot.resolveCitation(id);
        if (citation != null) {
          refs.add(_citationToSourceReference(citation, citations.figures));
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

  SourceReference _citationToSourceReference(Citation c, CitedFigures cited) {
    final figures = <Figure>[];
    for (final ref in c.pictureRefs ?? const <String>[]) {
      final bytes = cited.pictureBytes(c.documentId, ref);
      if (bytes == null) continue;
      final caption = cited.pictureCaption(c.documentId, ref);
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

/// A turn's accumulated citations: the union of cited chunk [ids] and the
/// union of inline [figures] observed across the turn's `StateDeltaEvent`s.
///
/// Bundling the two keeps them in lockstep — the live orchestrator and the
/// history replay both fold with [CitationExtractor.accumulate] and read back
/// with [CitationExtractor.resolve], so they cannot drift. Immutable; [merge]
/// returns a new union.
@immutable
class TurnCitations {
  /// Wraps an already-computed [ids] set and [figures] union. [ids] is copied
  /// into an unmodifiable set so the instance cannot be mutated through the
  /// reference passed in.
  TurnCitations(Set<String> ids, this.figures) : ids = Set.unmodifiable(ids);

  /// An empty accumulator — the identity element for [merge] and the turn-start
  /// value.
  const TurnCitations.empty()
      : ids = const {},
        figures = const CitedFigures.empty();

  /// Chunk ids cited so far this turn.
  final Set<String> ids;

  /// Inline figure bytes and captions retrieved so far this turn. The citing
  /// subset is selected later, when a citation's `pictureRefs` are resolved.
  final CitedFigures figures;

  /// The union of this and [other]'s ids and figures.
  TurnCitations merge(TurnCitations other) => TurnCitations(
        {...ids, ...other.ids},
        figures.merge(other.figures),
      );
}
