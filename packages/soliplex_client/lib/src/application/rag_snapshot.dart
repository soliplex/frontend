import 'dart:convert';
import 'dart:typed_data';

import 'package:soliplex_client/src/domain/surface.dart';
import 'package:soliplex_client/src/schema/agui_features/rag.dart';
import 'package:soliplex_client/src/schema/agui_features/rag_v040.dart';
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

/// Version-agnostic view of the backend's `rag`-namespaced AG-UI state.
///
/// The backend ships two wire shapes today:
///
/// - **haiku.rag 0.40** emits `citations` as a list of inline [Citation]
///   objects, alongside deprecated `qa_history`, `documents`, and
///   `reports` fields. See `rag_v040.dart`.
/// - **haiku.rag 0.42+** emits `citations` as a list of chunk ids, with a
///   separate `citation_index` map resolving each id to a [Citation]. See
///   `rag.dart`.
///
/// [RagSnapshot.fromJson] dispatches on wire shape today because the
/// backend has no explicit `schema_version` field. When that field is
/// added, only [RagSnapshot.fromJson] needs to change — everything above
/// this interface continues to depend on the two operations below and is
/// unaffected.
///
/// Version-specific fields (e.g. `qaHistory` on 0.40, `searches` on either
/// version) are reachable via the concrete schema types
/// ([RagV040] in `rag_v040.dart`, [Rag] in `rag.dart`) and are out of
/// scope for this interface until a consumer needs them.
abstract class RagSnapshot {
  /// Chunk ids of citations present in the current state. Under 0.42
  /// lifecycle these are cleared at each invocation start; under 0.40
  /// they accumulate across the thread.
  List<String> get citationIds;

  /// Resolves a chunk id to a full [Citation], or null if not present.
  Citation? resolveCitation(String id);

  /// Decoded bytes for a directly-retrieved (stage-1) picture ref, or null
  /// when the state carries no bytes for it (stage-2 / unknown).
  Uint8List? pictureBytes(String documentId, String ref);

  /// Caption text for a directly-retrieved picture ref, or null when the state
  /// carries none.
  String? pictureCaption(String documentId, String ref);

  /// Parses a `rag`-namespaced state map into the appropriate variant.
  ///
  /// Detection is shape-based today. When the backend adds a
  /// `schema_version` field the body of this factory becomes a switch on
  /// that field, with shape-sniffing retained only as a legacy fallback.
  static RagSnapshot fromJson(Map<String, dynamic> json) {
    return _isV040(json)
        ? RagV040Snapshot.fromJson(json)
        : RagV042Snapshot.fromJson(json);
  }
}

/// Returns true if [json] carries the 0.40 RAG state shape.
///
/// Signals, in order of decisiveness:
/// 1. `citations` is a non-empty list whose first element is a Map —
///    conclusive, since 0.42's `citations` holds strings.
/// 2. `citation_index` is present — conclusive for 0.42 (0.40 has no
///    such field).
/// 3. Any of `qa_history`, `documents`, `reports` is present —
///    0.40-exclusive fields (removed in 0.42). Covers cases where
///    `citations` is empty/absent.
/// 4. Default to 0.42 (the target schema).
bool _isV040(Map<String, dynamic> json) {
  final citations = json['citations'];
  if (citations is List && citations.isNotEmpty && citations.first is Map) {
    return true;
  }
  if (json.containsKey('citation_index')) return false;
  if (json.containsKey('qa_history') ||
      json.containsKey('documents') ||
      json.containsKey('reports')) {
    return true;
  }
  return false;
}

/// [RagSnapshot] backed by the haiku.rag 0.40 wire shape.
///
/// The snapshot deliberately consumes only `citations` (as a list of
/// inline [Citation] objects). Other 0.40 fields are accessible via
/// `RagV040.fromJson` in `rag_v040.dart`.
class RagV040Snapshot implements RagSnapshot {
  RagV040Snapshot._(this._byId, this._pictures);

  /// Parses inline Citations from 0.40-shaped JSON. Malformed entries
  /// (non-Map or invalid Citation payloads) are logged and skipped so
  /// that one bad entry does not take down an otherwise-valid snapshot.
  factory RagV040Snapshot.fromJson(Map<String, dynamic> json) {
    final raw = json['citations'];
    final byId = <String, Citation>{};
    if (raw is List) {
      for (var i = 0; i < raw.length; i++) {
        final entry = raw[i];
        if (entry is! Map<String, dynamic>) {
          _logger.warning(
            'RagV040Snapshot: skipping non-Map citations[$i] '
            '(runtimeType=${entry.runtimeType}).',
          );
          continue;
        }
        try {
          final citation = Citation.fromJson(entry);
          byId[citation.chunkId] = citation;
        } on Object catch (error, stackTrace) {
          _logger.warning(
            'RagV040Snapshot: failed to parse citations[$i] as Citation; '
            'present keys: ${entry.keys.toList()}.',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    }
    return RagV040Snapshot._(byId, _indexPictures(json));
  }

  final Map<String, Citation> _byId;
  final _PictureIndex _pictures;

  @override
  List<String> get citationIds => _byId.keys.toList();

  @override
  Citation? resolveCitation(String id) => _byId[id];

  @override
  Uint8List? pictureBytes(String documentId, String ref) =>
      _decodePicture(_pictures.bytes, documentId, ref);

  @override
  String? pictureCaption(String documentId, String ref) =>
      _pictures.captions[_pictureKey(documentId, ref)];
}

/// [RagSnapshot] backed by the haiku.rag 0.42 wire shape.
///
/// Parses `citations` and `citation_index` entry-by-entry rather than
/// delegating to [Rag.fromJson], which uses hard casts
/// (`List<String>.from(...)` / `Map<String, Citation>.from(...)`) that
/// throw on any malformed entry, taking down an otherwise-valid
/// snapshot. The
/// snapshot contract is narrow (just `citationIds` + `resolveCitation`),
/// so a resilient per-entry parse is correct here. Other 0.42 fields
/// are still reachable via [Rag.fromJson] in `rag.dart`.
class RagV042Snapshot implements RagSnapshot {
  RagV042Snapshot._(this._citationIds, this._index, this._pictures);

  /// Parses a 0.42-shaped payload with per-entry resilience: malformed
  /// entries in `citations` / `citation_index` are logged and skipped.
  factory RagV042Snapshot.fromJson(Map<String, dynamic> json) {
    final ids = <String>[];
    final rawCitations = json['citations'];
    if (rawCitations is List) {
      for (var i = 0; i < rawCitations.length; i++) {
        final entry = rawCitations[i];
        if (entry is String) {
          ids.add(entry);
        } else {
          _logger.warning(
            'RagV042Snapshot: skipping non-String citations[$i] '
            '(runtimeType=${entry.runtimeType}).',
          );
        }
      }
    }

    final index = <String, Citation>{};
    final rawIndex = json['citation_index'];
    if (rawIndex is Map) {
      for (final entry in rawIndex.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String) {
          _logger.warning(
            'RagV042Snapshot: skipping non-String citation_index key '
            '(runtimeType=${key.runtimeType}).',
          );
          continue;
        }
        if (value is! Map<String, dynamic>) {
          _logger.warning(
            'RagV042Snapshot: skipping citation_index[$key] with '
            'non-Map value (runtimeType=${value.runtimeType}).',
          );
          continue;
        }
        try {
          index[key] = Citation.fromJson(value);
        } on Object catch (error, stackTrace) {
          _logger.warning(
            'RagV042Snapshot: failed to parse citation_index[$key] as '
            'Citation; present keys: ${value.keys.toList()}.',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    }

    return RagV042Snapshot._(ids, index, _indexPictures(json));
  }

  final List<String> _citationIds;
  final Map<String, Citation> _index;
  final _PictureIndex _pictures;

  @override
  List<String> get citationIds => _citationIds;

  @override
  Citation? resolveCitation(String id) => _index[id];

  @override
  Uint8List? pictureBytes(String documentId, String ref) =>
      _decodePicture(_pictures.bytes, documentId, ref);

  @override
  String? pictureCaption(String documentId, String ref) =>
      _pictures.captions[_pictureKey(documentId, ref)];
}

/// Projects a [RagSnapshot] from the full agent-state map.
///
/// Reads the [`ragStateKey`] slice and dispatches to the
/// version-aware [RagSnapshot.fromJson]. Returns null when the
/// namespace is absent or malformed (rather than a sentinel empty
/// snapshot) so consumers can distinguish "no rag activity yet"
/// from "rag activity but zero citations."
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
