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
  'citations',
  'document_filter',
  'documents',
  'qa_history',
  'reports',
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
/// Uses length-based detection: compares `len(previous)` vs `len(current)`
/// to find new entries at indices `[previousLength, currentLength)`.
class CitationExtractor {
  /// Extracts source references from entries added since [previousState].
  ///
  /// Returns an empty list if:
  /// - No recognized state format is found
  /// - Current has same or fewer entries than previous (FIFO rotation)
  /// - New entries have no citations
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
    // Treat non-Map previous as empty; citations may be re-extracted.
    final previousData =
        rawPrevious is Map<String, dynamic> ? rawPrevious : null;

    final previousLength = _getQaHistoryLength(previousData);
    final currentLength = _getQaHistoryLength(currentData);

    _warnUnknownKeys(currentData);

    if (currentLength <= previousLength) return [];

    try {
      // Parses the full Rag state to validate the complete schema contract.
      // If this throws, a malformed unrelated field (e.g. reports) will lose
      // valid citations too. If that becomes a problem, fall back to parsing
      // qa_history entries individually in the catch block.
      final rag = Rag.fromJson(currentData);
      final qaHistory = rag.qaHistory ?? [];

      return qaHistory
          .sublist(previousLength)
          .expand(_extractFromQaHistoryEntry)
          .toList();
    } catch (e, stackTrace) {
      _logFromJsonDiagnostic('Rag', currentData, e, stackTrace);
      return [];
    }
  }

  int _getQaHistoryLength(Map<String, dynamic>? data) {
    if (data == null) return 0;
    final qaHistory = data['qa_history'];
    if (qaHistory == null) return 0;
    if (qaHistory is! List) {
      developer.log(
        'Expected qa_history to be List, got ${qaHistory.runtimeType}.',
        name: 'soliplex_client.citation_extractor',
        level: 900,
      );
      developer.log(
        'qa_history value: $qaHistory',
        name: 'soliplex_client.citation_extractor',
        level: 700,
      );
      return 0;
    }
    return qaHistory.length;
  }

  List<SourceReference> _extractFromQaHistoryEntry(QaHistoryEntry entry) {
    final citations = entry.citations ?? [];
    return citations.map(_citationToSourceReference).toList();
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
