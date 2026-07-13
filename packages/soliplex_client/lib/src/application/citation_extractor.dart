import 'dart:typed_data';

import 'package:soliplex_client/src/application/rag_snapshot.dart';
import 'package:soliplex_client/src/domain/source_reference.dart';
import 'package:soliplex_client/src/schema/agui_features/rag.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final _logger =
    LogManager.instance.getLogger('soliplex_client.citation_extractor');

/// Extracts new [SourceReference]s by comparing AG-UI state snapshots.
///
/// **Schema firewall**: this file and [RagSnapshot] in
/// `rag_snapshot.dart` are the only places that import the schema-mirror
/// types in `rag.dart` / `rag_v040.dart`. When backend schemas
/// change, updates are confined to `rag_snapshot.dart`'s detector and
/// implementations.
///
/// The algorithm is version-agnostic: resolve each state into a
/// [RagSnapshot], take the difference of `citationIds`, and resolve
/// each new id back to a full [Citation]. The two wire shapes differ
/// only in how ids and Citations are laid out — both expose the same
/// two operations via [RagSnapshot].
class CitationExtractor {
  /// Extracts source references added since [previousState].
  ///
  /// Returns an empty list if:
  /// - The current state has no `rag` namespace or an unparseable one.
  /// - Current citations are a subset of previous.
  /// - New ids cannot be resolved against the snapshot.
  List<SourceReference> extractNew(
    Map<String, dynamic> previousState,
    Map<String, dynamic> currentState,
  ) {
    final currentRag = _snapshot(currentState);
    if (currentRag == null) return [];

    final previousRag = _snapshot(previousState);
    final previousIds = (previousRag?.citationIds ?? const <String>[]).toSet();

    final newIds = currentRag.citationIds
        .where((id) => !previousIds.contains(id))
        .toList();
    if (newIds.isEmpty) return [];

    return newIds
        .map(currentRag.resolveCitation)
        .whereType<Citation>()
        .map((c) => _citationToSourceReference(c, currentRag))
        .toList();
  }

  /// Resolves [state]'s `rag` namespace into a [RagSnapshot], or null
  /// when the key is absent, not a Map, or fails to parse as either
  /// wire shape.
  RagSnapshot? _snapshot(Map<String, dynamic> state) {
    final raw = state[ragStateKey];
    if (raw == null) return null;
    if (raw is! Map<String, dynamic>) {
      _logger.warning(
        'Expected rag state to be Map<String, dynamic>, '
        'got ${raw.runtimeType}.',
      );
      return null;
    }
    try {
      return RagSnapshot.fromJson(raw);
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'Failed to parse rag state as either wire shape.',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  SourceReference _citationToSourceReference(Citation c, RagSnapshot rag) {
    final pictureRefs = c.pictureRefs ?? const <String>[];
    final pictureBytes = <String, Uint8List>{};
    for (final ref in pictureRefs) {
      final bytes = rag.pictureBytes(c.documentId, ref);
      if (bytes != null) pictureBytes[ref] = bytes;
    }
    return SourceReference(
      documentId: c.documentId,
      documentUri: c.documentUri,
      content: c.content,
      chunkId: c.chunkId,
      documentTitle: c.documentTitle,
      headings: c.headings ?? [],
      pageNumbers: c.pageNumbers ?? [],
      docItemRefs: c.docItemRefs ?? [],
      pictureRefs: pictureRefs,
      pictureBytes: pictureBytes,
      chunkIds: c.chunkIds ?? [],
      index: c.index,
    );
  }
}
