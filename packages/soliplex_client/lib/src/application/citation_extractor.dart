import 'dart:developer' as developer;

import 'package:soliplex_client/src/domain/source_reference.dart';
import 'package:soliplex_client/src/schema/agui_features/rag.dart';

void _logFromJsonDiagnostic(
  String className,
  Map<String, dynamic> json,
  Object error,
  StackTrace stackTrace,
) {
  final nullKeys =
      json.entries.where((e) => e.value == null).map((e) => e.key).toList();
  final presentKeys = json.keys.toList();

  final message = '$className.fromJson failed ($error). '
      'Null keys: $nullKeys. Present keys: $presentKeys.';

  developer.log(
    message,
    name: 'soliplex_client.citation_extractor',
    level: 900,
    error: error,
    stackTrace: stackTrace,
  );
}

/// Known keys in the backend RAGState schema.
const knownRagKeys = {
  'citation_index',
  'citations',
  'document_filter',
  'searches',
};

/// Logs a warning for any keys in [data] not in the backend RAGState schema.
void _warnUnknownKeys(Map<String, dynamic> data) {
  final unknown = data.keys.where((k) => !knownRagKeys.contains(k)).toList();
  if (unknown.isEmpty) return;
  developer.log(
    'rag state contains unknown keys: $unknown. '
    'Schema may be out of date with backend.',
    name: 'soliplex_client.citation_extractor',
    level: 800,
  );
}

/// The AG-UI state namespace key for RAG state.
///
/// Must match the backend's `STATE_NAMESPACE` in `haiku.rag.skills.rag`.
const ragStateKey = 'rag';

/// Extracts new [SourceReference]s by comparing AG-UI state snapshots.
///
/// This is the **schema firewall**: the only file that imports schema types.
/// When generated schema classes change, only this file needs updating.
///
/// `citations` is a flat list of chunk ids cited during the current
/// invocation. The lifespan clears it at each invocation start, so new
/// references are ids in the current list that are not in the previous
/// snapshot; ids are resolved against `citation_index`.
class CitationExtractor {
  /// Extracts source references added since [previousState].
  ///
  /// Returns an empty list if:
  /// - No recognized state format is found
  /// - Current citations are a subset of previous
  /// - New ids cannot be resolved against `citation_index`
  List<SourceReference> extractNew(
    Map<String, dynamic> previousState,
    Map<String, dynamic> currentState,
  ) {
    return _extractFromRagState(previousState, currentState);
  }

  List<SourceReference> _extractFromRagState(
    Map<String, dynamic> previousState,
    Map<String, dynamic> currentState,
  ) {
    final rawPrevious = previousState[ragStateKey];
    final rawCurrent = currentState[ragStateKey];

    if (rawCurrent is! Map<String, dynamic>) {
      if (rawCurrent != null) {
        developer.log(
          'Expected rag state to be Map<String, dynamic>, '
          'got ${rawCurrent.runtimeType}.',
          name: 'soliplex_client.citation_extractor',
          level: 900,
        );
        developer.log(
          'rag state value: $rawCurrent',
          name: 'soliplex_client.citation_extractor',
          level: 700,
        );
      }
      return [];
    }
    final currentData = rawCurrent;

    if (rawPrevious != null && rawPrevious is! Map<String, dynamic>) {
      developer.log(
        'Expected previous rag state to be Map<String, dynamic>, '
        'got ${rawPrevious.runtimeType}.',
        name: 'soliplex_client.citation_extractor',
        level: 900,
      );
      developer.log(
        'Previous rag state value: $rawPrevious',
        name: 'soliplex_client.citation_extractor',
        level: 700,
      );
    }
    final previousData =
        rawPrevious is Map<String, dynamic> ? rawPrevious : null;

    _warnUnknownKeys(currentData);

    final previousIds = _getCitationIds(previousData).toSet();
    final currentIds = _getCitationIds(currentData);
    final newIds =
        currentIds.where((id) => !previousIds.contains(id)).toList();
    if (newIds.isEmpty) return [];

    try {
      final rag = Rag.fromJson(currentData);
      final citationIndex = rag.citationIndex ?? {};

      return newIds
          .map((id) => citationIndex[id])
          .whereType<Citation>()
          .map(_citationToSourceReference)
          .toList();
    } catch (e, stackTrace) {
      _logFromJsonDiagnostic('Rag', currentData, e, stackTrace);
      return [];
    }
  }

  List<String> _getCitationIds(Map<String, dynamic>? data) {
    if (data == null) return const [];
    final citations = data['citations'];
    if (citations == null) return const [];
    if (citations is! List) {
      developer.log(
        'Expected citations to be List, got ${citations.runtimeType}.',
        name: 'soliplex_client.citation_extractor',
        level: 900,
      );
      developer.log(
        'citations value: $citations',
        name: 'soliplex_client.citation_extractor',
        level: 700,
      );
      return const [];
    }
    return citations.whereType<String>().toList();
  }

  SourceReference _citationToSourceReference(Citation c) {
    return SourceReference(
      documentId: c.documentId,
      documentUri: c.documentUri,
      content: c.content,
      chunkId: c.chunkId,
      documentTitle: c.documentTitle,
      headings: c.headings ?? [],
      pageNumbers: c.pageNumbers ?? [],
      index: c.index,
    );
  }
}
