import 'dart:convert';
import 'dart:typed_data';

import 'package:soliplex_client/src/domain/surface.dart';
import 'package:soliplex_client/src/schema/agui_features/rag.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final _logger = LogManager.instance.getLogger('soliplex_client.rag_snapshot');

/// The AG-UI state namespace key for RAG state.
///
/// Must match the backend's `STATE_NAMESPACE` in `haiku.rag.skills.rag`.
const ragStateKey = 'rag';

const String _ragDocumentFilterKey = 'document_filter';

/// Builds a partial `aguiState` overlay that sets the rag namespace's
/// `document_filter`. Other rag fields are left untouched by the
/// backend's state-merge semantics.
///
/// Centralizes the wire-format string keys (`'rag'`,
/// `'document_filter'`) so UI code doesn't hardcode them.
Map<String, dynamic> buildRagDocumentFilterOverlay(String? filter) {
  return {
    ragStateKey: <String, dynamic>{
      _ragDocumentFilterKey: filter,
    },
  };
}

/// Composite key for the picture-bytes index: document id + picture self_ref.
///
/// A named record so the two same-typed components can't be transposed at a
/// call site.
typedef _PictureKey = ({String documentId, String ref});

_PictureKey _pictureKey(String documentId, String ref) =>
    (documentId: documentId, ref: ref);

/// The two picture indexes built from a `rag` state's `searches`, both keyed
/// by [_pictureKey]: base64 `bytes` for directly-retrieved figures and their
/// `captions`. Captions are indexed only for rows that carry `image_data`, so
/// a caption only surfaces for a figure that renders inline.
typedef _PictureIndex = ({
  Map<_PictureKey, String> bytes,
  Map<_PictureKey, String> captions,
});

/// Builds the picture indexes from a `rag` state's `searches`.
///
/// The builder reads only the fields it needs — `document_id` (raw),
/// `image_data`, and `picture_captions` (via the shared parsers) — rather than
/// building a whole [SearchResult], so an unrelated malformed field on a row
/// can't drop that row's figures. A malformed shape is skipped and logged; a
/// row that simply carries no `image_data` is silently ignored (the normal
/// figure-less case).
_PictureIndex _indexPictures(Map<String, dynamic> json) {
  final bytes = <_PictureKey, String>{};
  final captions = <_PictureKey, String>{};
  final raw = json['searches'];
  if (raw is! Map) {
    if (raw != null) {
      _logger.warning(
        'RagSnapshot: expected `searches` to be a Map, '
        'got ${raw.runtimeType}; no cited-figure bytes indexed.',
      );
    }
    return (bytes: bytes, captions: captions);
  }
  for (final search in raw.entries) {
    final results = search.value;
    if (results is! List) {
      _logger.warning(
        'RagSnapshot: skipping searches[${search.key}] with non-List value '
        '(runtimeType=${results.runtimeType}).',
      );
      continue;
    }
    for (var i = 0; i < results.length; i++) {
      final item = results[i];
      if (item is! Map<String, dynamic>) {
        _logger.warning(
          'RagSnapshot: skipping non-Map searches[${search.key}][$i] '
          '(runtimeType=${item.runtimeType}).',
        );
        continue;
      }
      final imageData = SearchResult.parseImageData(item['image_data']);
      if (imageData.isEmpty) continue;
      final docId = item['document_id'];
      if (docId is! String) {
        _logger.warning(
          'RagSnapshot: dropping figures on searches[${search.key}][$i] '
          'with non-String document_id (runtimeType=${docId.runtimeType}).',
        );
        continue;
      }
      final captionData =
          SearchResult.parsePictureCaptions(item['picture_captions']);
      imageData.forEach((ref, b64) {
        bytes.putIfAbsent(_pictureKey(docId, ref), () => b64);
      });
      captionData.forEach((ref, text) {
        if (text.isNotEmpty) {
          captions.putIfAbsent(_pictureKey(docId, ref), () => text);
        }
      });
    }
  }
  return (bytes: bytes, captions: captions);
}

/// Decodes an indexed picture ref to bytes, or null when absent / undecodable.
Uint8List? _decodePicture(
  Map<_PictureKey, String> index,
  String documentId,
  String ref,
) {
  final b64 = index[_pictureKey(documentId, ref)];
  if (b64 == null) return null;
  try {
    return base64Decode(b64);
  } on FormatException catch (error) {
    _logger.warning(
      'RagSnapshot: picture ref "$ref" has undecodable base64; dropped.',
      error: error,
    );
    return null;
  }
}

/// A read-model view of a RAG skill's AG-UI state slice.
///
/// Every RAG-producing skill publishes the same citation shape under its
/// own namespace — `rag` and `analysis` both carry `citations` as a list
/// of chunk ids and a `citation_index` map resolving each id to a full
/// [Citation]. This snapshot exposes only what citation extraction and
/// figure rendering need: the citation ids, id → [Citation] resolution,
/// and inline picture bytes / captions. Other fields (e.g. `searches`,
/// `document_filter`, and `analysis`'s `executions`) are read through a
/// resilient per-entry reader when a consumer needs them, or ignored.
///
/// [RagSnapshot.fromJson] parses `citations` and `citation_index`
/// entry-by-entry so one malformed entry is logged and skipped rather than
/// taking down an otherwise-valid snapshot. The snapshot contract is narrow,
/// so a resilient per-entry parse is the right trade here.
class RagSnapshot {
  RagSnapshot._(this._citationIds, this._index, this._pictures);

  /// Parses a `rag`-namespaced state map, with per-entry resilience:
  /// malformed entries in `citations` / `citation_index` are logged and
  /// skipped so one bad entry does not take down the whole snapshot.
  factory RagSnapshot.fromJson(Map<String, dynamic> json) {
    final ids = <String>[];
    final rawCitations = json['citations'];
    if (rawCitations is List) {
      for (var i = 0; i < rawCitations.length; i++) {
        final entry = rawCitations[i];
        if (entry is String) {
          ids.add(entry);
        } else {
          _logger.warning(
            'RagSnapshot: skipping non-String citations[$i] '
            '(runtimeType=${entry.runtimeType}).',
          );
        }
      }
    }

    final index = <String, Citation>{};
    final rawIndex = json[_citationIndexKey];
    if (rawIndex is Map) {
      for (final entry in rawIndex.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String) {
          _logger.warning(
            'RagSnapshot: skipping non-String citation_index key '
            '(runtimeType=${key.runtimeType}).',
          );
          continue;
        }
        if (value is! Map<String, dynamic>) {
          _logger.warning(
            'RagSnapshot: skipping citation_index[$key] with '
            'non-Map value (runtimeType=${value.runtimeType}).',
          );
          continue;
        }
        try {
          index[key] = Citation.fromJson(value);
        } on Object catch (error, stackTrace) {
          _logger.warning(
            'RagSnapshot: failed to parse citation_index[$key] as '
            'Citation; present keys: ${value.keys.toList()}.',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    }

    return RagSnapshot._(ids, index, _indexPictures(json));
  }

  /// Wire key marking a citation-bearing skill-state block: the
  /// `id → Citation` map the extractor needs to render a source.
  static const _citationIndexKey = 'citation_index';

  /// Every citation-bearing namespace block in a full agent-state map,
  /// identified by a [`_citationIndexKey`] map. Non-citation namespaces
  /// (e.g. `bubble-sandbox`) and non-Map or mistyped blocks are skipped,
  /// so this is the single place that knows how a citation block is shaped.
  ///
  /// [RagSnapshot.fromJson] is resilient by construction and should not
  /// throw, but a block that fails to parse is caught and skipped rather
  /// than propagated: one malformed namespace must not take down the
  /// others, nor abort the unguarded replay path that consumes this.
  static List<RagSnapshot> extractAll(Map<String, dynamic> state) {
    final snapshots = <RagSnapshot>[];
    for (final raw in state.values) {
      if (raw is! Map<String, dynamic> || raw[_citationIndexKey] is! Map) {
        continue;
      }
      try {
        snapshots.add(RagSnapshot.fromJson(raw));
      } on Object catch (error, stackTrace) {
        _logger.warning(
          'RagSnapshot: skipping a citation namespace that failed to parse.',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return snapshots;
  }

  final List<String> _citationIds;
  final Map<String, Citation> _index;
  final _PictureIndex _pictures;

  /// Chunk ids of the citations present in the current state. The backend's
  /// state lifecycle clears these at each invocation start.
  List<String> get citationIds => _citationIds;

  /// Resolves a chunk id to a full [Citation], or null if not present.
  Citation? resolveCitation(String id) => _index[id];

  /// Decoded bytes for a directly-retrieved (stage-1) picture ref, or null
  /// when the state carries no bytes for it (stage-2 / unknown).
  Uint8List? pictureBytes(String documentId, String ref) =>
      _decodePicture(_pictures.bytes, documentId, ref);

  /// Caption text for a directly-retrieved picture ref, or null when the state
  /// carries none.
  String? pictureCaption(String documentId, String ref) =>
      _pictures.captions[_pictureKey(documentId, ref)];
}

/// Projects a [RagSnapshot] from the full agent-state map.
///
/// Reads the [`ragStateKey`] slice and delegates to
/// [RagSnapshot.fromJson]. Returns null when the namespace is absent or
/// malformed (rather than a sentinel empty snapshot) so consumers can
/// distinguish "no rag activity yet" from "rag activity but zero
/// citations."
///
/// This is the first conformance of the [StateProjection] contract
/// against existing pre-projection code in `soliplex_client`. The
/// `RagSnapshot` machinery predates the GenUI plan; wrapping it in
/// a projection class is purely glue — every byte of parsing logic
/// stays in [RagSnapshot.fromJson].
class RagSnapshotProjection extends StateProjection<RagSnapshot?> {
  /// Const constructor — the projection is stateless.
  const RagSnapshotProjection();

  @override
  RagSnapshot? project(Map<String, dynamic> agentState) {
    final raw = agentState[ragStateKey];
    if (raw is! Map<String, dynamic>) return null;
    return RagSnapshot.fromJson(raw);
  }
}
