import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:soliplex_client/src/domain/surface.dart';
import 'package:soliplex_client/src/schema/agui_features/rag.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final _logger = LogManager.instance.getLogger('soliplex_client.rag_snapshot');

/// The AG-UI state namespace key for RAG state.
///
/// Must match the backend's `STATE_NAMESPACE` in
/// `haiku.rag.capabilities.rag`.
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

/// A union of inline figure bytes and captions retrieved across some scope,
/// keyed by [_pictureKey] (`(documentId, ref)`): base64 `bytes` for directly-
/// retrieved figures and their `captions`. Captions are indexed only for rows
/// that carry `image_data`, so a caption only surfaces for a figure that
/// renders inline. The index holds every retrieved figure; the citing subset
/// is selected later, when a citation's `pictureRefs` are resolved.
///
/// The backend clears a `rag` state's `searches` — the only source of these
/// bytes — at the start of every run, so a run's state carries only its own
/// figures. Accumulating a [CitedFigures] union across a turn's runs preserves
/// earlier runs' figures. Bytes for a given `(documentId, ref)` are
/// identity-stable, so [merge] is an unambiguous union (no precedence to
/// resolve).
@immutable
class CitedFigures {
  const CitedFigures._(this._bytes, this._captions);

  /// An empty union — the identity element for [merge].
  const CitedFigures.empty()
      : _bytes = const {},
        _captions = const {};

  /// Builds the figure union from a single `rag` state block's `searches`.
  ///
  /// Reads only the fields it needs — `document_id` (raw), `image_data`, and
  /// `picture_captions` (via the shared parsers) — rather than building a whole
  /// [SearchResult], so an unrelated malformed field on a row can't drop that
  /// row's figures. A malformed shape is skipped and logged; a row that simply
  /// carries no `image_data` is silently ignored (the normal figure-less case).
  factory CitedFigures.fromSearches(Map<String, dynamic> ragBlock) {
    final bytes = <_PictureKey, String>{};
    final captions = <_PictureKey, String>{};
    final raw = ragBlock[RagSnapshot._searchesKey];
    if (raw is! Map) {
      if (raw != null) {
        _logger.warning(
          'RagSnapshot: expected `searches` to be a Map, '
          'got ${raw.runtimeType}; no cited-figure bytes indexed.',
        );
      }
      return CitedFigures._(bytes, captions);
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
    return CitedFigures._(bytes, captions);
  }

  final Map<_PictureKey, String> _bytes;
  final Map<_PictureKey, String> _captions;

  /// The union of this and [other]. Identity-stable bytes make this
  /// unambiguous, so an existing entry is kept (first-wins == last-wins).
  /// Short-circuits when either side is empty.
  CitedFigures merge(CitedFigures other) {
    if (other._bytes.isEmpty && other._captions.isEmpty) return this;
    if (_bytes.isEmpty && _captions.isEmpty) return other;
    return CitedFigures._(
      {...other._bytes, ..._bytes},
      {...other._captions, ..._captions},
    );
  }

  /// Decoded bytes for a directly-retrieved (stage-1) picture ref, or null when
  /// the union carries no bytes for it (stage-2 / unknown) or they don't decode.
  Uint8List? pictureBytes(String documentId, String ref) {
    final b64 = _bytes[_pictureKey(documentId, ref)];
    if (b64 == null) return null;
    try {
      return base64Decode(b64);
    } on FormatException catch (error) {
      _logger.warning(
        'RagSnapshot: picture ref "$ref" for document "$documentId" has '
        'undecodable base64; dropped.',
        attributes: {'failure': describeFailure(error)},
      );
      return null;
    }
  }

  /// Caption text for a directly-retrieved picture ref, or null when the union
  /// carries none.
  String? pictureCaption(String documentId, String ref) =>
      _captions[_pictureKey(documentId, ref)];
}

/// A read-model view of a RAG capability's AG-UI state slice.
///
/// Every RAG-producing capability publishes the same citation shape under its
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
  RagSnapshot._(this._citationIds, this._index, this._figures);

  /// Parses a `rag`-namespaced state map, with per-entry resilience:
  /// malformed entries in `citations` / `citation_index` are logged and
  /// skipped so one bad entry does not take down the whole snapshot.
  factory RagSnapshot.fromJson(Map<String, dynamic> json) {
    final ids = <String>[];
    final rawCitations = json[_citationsKey];
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
    } else if (rawCitations != null) {
      _logger.warning(
        'RagSnapshot: `citations` present but not a List '
        '(runtimeType=${rawCitations.runtimeType}); no citation ids read.',
      );
    }

    final index = <String, Citation>{};
    final rawIndex = json[_citationIndexKey];
    if (rawIndex is! Map) {
      if (rawIndex != null) {
        _logger.warning(
          'RagSnapshot: `citation_index` present but not a Map '
          '(runtimeType=${rawIndex.runtimeType}); no citations resolvable.',
        );
      }
    } else {
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

    return RagSnapshot._(ids, index, CitedFigures.fromSearches(json));
  }

  /// Wire key marking a citation-bearing capability-state block: the
  /// `id → Citation` map the extractor needs to render a source.
  static const _citationIndexKey = 'citation_index';

  /// Wire keys the backend clears at the start of every run in which the
  /// owning capability loads, so their contents are scoped to a single run: the
  /// cited chunk ids, the retrieval results their inline figures come from, and
  /// the analysis namespace's code-execution log. A capability that never loads
  /// never clears, which is why a run is seeded via [withEmptyRunScopedKeys]
  /// rather than trusting the backend to have cleared.
  static const _citationsKey = 'citations';
  static const _searchesKey = 'searches';
  static const _executionsKey = 'executions';

  /// Whether [raw] is a citation-bearing namespace block — the single predicate
  /// [extractAll] and [withEmptyRunScopedKeys] share, so what one extracts from
  /// and what the other clears cannot drift apart. Drift is silent in both
  /// directions: clearing less than is extracted over-credits stale citations,
  /// clearing more loses live ones.
  static bool _isCitationBearing(Object? raw) =>
      raw is Map<String, dynamic> && raw[_citationIndexKey] is Map;

  /// Every citation-bearing namespace block in a full agent-state map,
  /// identified by a [`_citationIndexKey`] map. Namespaces without one, and
  /// non-Map or mistyped blocks, are skipped, so this is the single place that
  /// knows how a citation block is shaped.
  ///
  /// When [namespaces] is given, only blocks under those keys are considered;
  /// otherwise every namespace in [state] is.
  ///
  /// [RagSnapshot.fromJson] is resilient by construction and should not
  /// throw, but a block that fails to parse is caught and skipped rather
  /// than propagated: one malformed namespace must not take down the
  /// others, nor abort the unguarded replay path that consumes this.
  static List<RagSnapshot> extractAll(
    Map<String, dynamic> state, {
    Set<String>? namespaces,
  }) {
    final snapshots = <RagSnapshot>[];
    for (final entry in state.entries) {
      if (namespaces != null && !namespaces.contains(entry.key)) continue;
      final raw = entry.value;
      if (!_isCitationBearing(raw)) continue;
      try {
        snapshots.add(RagSnapshot.fromJson(raw as Map<String, dynamic>));
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

  /// [state] with every citation-bearing namespace's run-scoped keys emptied.
  ///
  /// The cumulative `citation_index` and every other field (notably
  /// `document_filter`) are preserved, and non-citation namespaces are copied
  /// through untouched. Seeding a run with this guarantees that any namespace
  /// carrying a non-empty `citations` in the run's terminal state snapshot
  /// populated it during that run, which is what lets the extractor credit a
  /// snapshot without knowing which capabilities the model actually invoked.
  ///
  /// Also keeps the request small: `searches` carries base64 figure bytes and
  /// `executions` captured stdout, both of which the backend discards on
  /// arrival.
  ///
  /// A key is only emptied when the namespace already carries it, mirroring the
  /// backend's per-field lookup — `rag` has no `executions`, and inventing one
  /// would make the outbound request misleading to read.
  static Map<String, dynamic> withEmptyRunScopedKeys(
    Map<String, dynamic> state,
  ) {
    final result = Map<String, dynamic>.of(state);
    final cleared = <String>[];
    for (final entry in state.entries) {
      final raw = entry.value;
      if (!_isCitationBearing(raw)) continue;
      raw as Map<String, dynamic>;
      final keys = [
        if (raw.containsKey(_citationsKey)) _citationsKey,
        if (raw.containsKey(_searchesKey)) _searchesKey,
        if (raw.containsKey(_executionsKey)) _executionsKey,
      ];
      final seeded = <String, dynamic>{
        ...raw,
        if (raw.containsKey(_citationsKey)) _citationsKey: <String>[],
        if (raw.containsKey(_searchesKey)) _searchesKey: <String, dynamic>{},
        if (raw.containsKey(_executionsKey)) _executionsKey: <dynamic>[],
      };
      final filter = seeded[_ragDocumentFilterKey];
      final index = raw[_citationIndexKey];
      final filterNote = filter is String
          ? '$_ragDocumentFilterKey: ${filter.length} chars'
          : 'no $_ragDocumentFilterKey';
      cleared.add(
        '${entry.key}(cleared: ${keys.join(',')}; '
        'kept $_citationIndexKey: ${index is Map ? index.length : 0} '
        'entries; $filterNote)',
      );
      result[entry.key] = seeded;
    }
    _logger.debug(
      cleared.isEmpty
          ? 'Seeded a run with no citation-bearing namespace to clear.'
          : 'Seeded a run with run-scoped keys cleared: '
              '${cleared.join(' ')}.',
    );
    return result;
  }

  final List<String> _citationIds;
  final Map<String, Citation> _index;
  final CitedFigures _figures;

  /// Chunk ids of the citations present in the current state. These are
  /// run-scoped: for a state that was seeded via [withEmptyRunScopedKeys] or
  /// produced by a capability that loaded, they are the ids cited by the run
  /// this state came from.
  List<String> get citationIds => _citationIds;

  /// Resolves a chunk id to a full [Citation], or null if not present.
  Citation? resolveCitation(String id) => _index[id];

  /// Inline figure bytes and captions carried by this snapshot's `searches`.
  CitedFigures get figures => _figures;
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
