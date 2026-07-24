import 'package:soliplex_client/src/application/rag_snapshot.dart';
import 'package:soliplex_client/src/domain/source_reference.dart';
import 'package:soliplex_client/src/schema/agui_features/rag.dart';
import 'package:soliplex_client/src/utils/source_url.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final _logger =
    LogManager.instance.getLogger('soliplex_client.citation_extractor');

/// Extracts new [SourceReference]s by comparing AG-UI state snapshots.
///
/// **Schema firewall**: this file and [RagSnapshot] in
/// `rag_snapshot.dart` are the only places that import the schema-mirror
/// types in `rag.dart`. When the backend citation shape changes, updates
/// are confined to `rag_snapshot.dart`.
///
/// The algorithm: collect every citation-bearing namespace in the state
/// (each RAG-producing skill — `rag`, `analysis`, … — publishes its own),
/// take the difference of their combined `citationIds`, and resolve each
/// new id back to a full [Citation].
class CitationExtractor {
  /// Extracts source references added since [previousState] across every
  /// citation-bearing namespace in the state.
  ///
  /// Returns an empty list if:
  /// - The current state carries no citation-bearing namespace.
  /// - Current citations are a subset of previous.
  /// - New ids cannot be resolved against any current snapshot.
  ///
  /// Ids are deduped across namespaces so a chunk cited in more than one
  /// namespace in a single turn yields a single reference.
  ///
  /// Never throws: a namespace whose block fails to parse is skipped by
  /// [RagSnapshot.extractAll], and everything after operates on already-
  /// parsed snapshots. The replay path relies on this — it calls this
  /// method without a surrounding guard.
  List<SourceReference> extractNew(
    Map<String, dynamic> previousState,
    Map<String, dynamic> currentState,
  ) {
    final currentSnapshots = RagSnapshot.extractAll(currentState);
    if (currentSnapshots.isEmpty) return [];

    final previousIds = <String>{
      for (final s in RagSnapshot.extractAll(previousState)) ...s.citationIds,
    };

    final newIds = <String>[];
    final seen = <String>{};
    for (final snapshot in currentSnapshots) {
      for (final id in snapshot.citationIds) {
        if (previousIds.contains(id)) continue;
        if (seen.add(id)) newIds.add(id);
      }
    }
    if (newIds.isEmpty) return [];

    final refs = <SourceReference>[];
    for (final id in newIds) {
      for (final snapshot in currentSnapshots) {
        final citation = snapshot.resolveCitation(id);
        if (citation != null) {
          refs.add(_citationToSourceReference(citation, snapshot));
          break;
        }
      }
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
