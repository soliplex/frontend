import 'dart:developer' as developer;

import 'package:soliplex_client/src/domain/surface.dart';
import 'package:soliplex_client/src/schema/agui_features/rag.dart';
import 'package:soliplex_client/src/schema/agui_features/rag_v040.dart';

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

/// Version-agnostic view of the backend's `rag`-namespaced AG-UI state.
///
/// The backend ships two wire shapes today:
///
/// - **haiku.rag 0.40** emits `citations` as a list of inline [Citation]
///   objects, alongside deprecated `qa_history`, `documents`, and
///   `reports` fields. See `rag_v040.dart`.
/// - **haiku.rag 0.42+** emits `citations` as a list of chunk ids, with a
///   separate `citation_index` map resolving each id to a [Citation]. See
///   `rag.dart` (the generated schema).
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
  RagV040Snapshot._(this._byId);

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
          developer.log(
            'RagV040Snapshot: skipping non-Map citations[$i] '
            '(runtimeType=${entry.runtimeType}).',
            name: 'soliplex_client.rag_snapshot',
            level: 900,
          );
          continue;
        }
        try {
          final citation = Citation.fromJson(entry);
          byId[citation.chunkId] = citation;
        } on Object catch (error, stackTrace) {
          developer.log(
            'RagV040Snapshot: failed to parse citations[$i] as Citation; '
            'present keys: ${entry.keys.toList()}.',
            name: 'soliplex_client.rag_snapshot',
            level: 900,
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    }
    return RagV040Snapshot._(byId);
  }

  final Map<String, Citation> _byId;

  @override
  List<String> get citationIds => _byId.keys.toList();

  @override
  Citation? resolveCitation(String id) => _byId[id];
}

/// [RagSnapshot] backed by the haiku.rag 0.42 wire shape.
///
/// Parses `citations` and `citation_index` entry-by-entry rather than
/// delegating to the generated [Rag.fromJson]: the generated code uses
/// hard casts (`List<String>.from(...)` /
/// `Map<String, Citation>.from(...)`) that throw on any malformed
/// entry, which would take down an otherwise-valid snapshot. The
/// snapshot contract is narrow (just `citationIds` + `resolveCitation`),
/// so a resilient per-entry parse is correct here. Other 0.42 fields
/// are still reachable via [Rag.fromJson] in `rag.dart`.
class RagV042Snapshot implements RagSnapshot {
  RagV042Snapshot._(this._citationIds, this._index);

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
          developer.log(
            'RagV042Snapshot: skipping non-String citations[$i] '
            '(runtimeType=${entry.runtimeType}).',
            name: 'soliplex_client.rag_snapshot',
            level: 900,
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
          developer.log(
            'RagV042Snapshot: skipping non-String citation_index key '
            '(runtimeType=${key.runtimeType}).',
            name: 'soliplex_client.rag_snapshot',
            level: 900,
          );
          continue;
        }
        if (value is! Map<String, dynamic>) {
          developer.log(
            'RagV042Snapshot: skipping citation_index[$key] with '
            'non-Map value (runtimeType=${value.runtimeType}).',
            name: 'soliplex_client.rag_snapshot',
            level: 900,
          );
          continue;
        }
        try {
          index[key] = Citation.fromJson(value);
        } on Object catch (error, stackTrace) {
          developer.log(
            'RagV042Snapshot: failed to parse citation_index[$key] as '
            'Citation; present keys: ${value.keys.toList()}.',
            name: 'soliplex_client.rag_snapshot',
            level: 900,
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
    }

    return RagV042Snapshot._(ids, index);
  }

  final List<String> _citationIds;
  final Map<String, Citation> _index;

  @override
  List<String> get citationIds => _citationIds;

  @override
  Citation? resolveCitation(String id) => _index[id];
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
