import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:soliplex_client/src/errors/exceptions.dart';
import 'package:soliplex_client/src/schema/agui_features/rag.dart';
import 'package:test/test.dart';

/// One schema type: each property's normalised type, and its required names.
typedef _Shape = ({Map<String, String> properties, Set<String> required});

/// Written by `tool/refresh_agui_feature_schemas.dart`; see
/// `docs/refreshing-backend-schema-snapshots.md`.
const _snapshotDir = 'test/schema/fixtures/agui_feature_schemas';

/// The snapshots the supported-backends policy requires: the haiku.rag
/// version `afsoc-rag` deploys, and the one backend `main` pins.
const _supportedSnapshots = ['haiku-rag-0.84.0.json', 'haiku-rag-0.87.0.json'];

/// Keys the frontend reads, per schema type, with the normalised schema type
/// its parser expects.
const _read = <String, Map<String, String>>{
  'rag': {
    'citations': 'list[string]',
    'citation_index': 'map[Citation]',
    'document_filter': 'string | null',
    'sources': 'list[string] | null',
    'searches': 'map[list[SearchResult]]',
  },
  'Citation': {
    'index': 'integer | null',
    'document_id': 'string',
    'source': 'string | null',
    'chunk_id': 'string',
    'document_uri': 'string',
    'document_title': 'string | null',
    'document_meta': 'map[any]',
    'page_numbers': 'list[integer]',
    'headings': 'list[string] | null',
    'content': 'string',
    'doc_item_refs': 'list[string]',
    'picture_refs': 'list[string]',
  },
  'SearchResult': {
    'document_id': 'string | null',
    'image_data': 'map[string] | null',
    'picture_captions': 'map[string]',
  },
};

/// Keys the frontend does not read yet, per schema type, with the roadmap item
/// that will read them. A "recommend declining" note is decided when that item
/// is picked up.
const _unread = <String, Map<String, String>>{
  'rag': {
    'evidence': 'consulted-not-cited; grounding indicator',
    'executions': 'executions panel',
  },
  'citation_policy': {'violations': 'grounding indicator'},
  'Citation': {
    'chunk_ids': 'retrieval panel',
    'chunk_meta': 'retrieval panel; recommend declining: raw third-party '
        'chunker metadata, no defined meaning',
  },
  'SearchResult': {
    'content': 'retrieval panel',
    'score': 'retrieval panel',
    'source': 'retrieval panel',
    'chunk_id': 'retrieval panel',
    'chunk_ids': 'retrieval panel',
    'chunk_meta': 'retrieval panel; recommend declining: raw third-party '
        'chunker metadata, no defined meaning',
    'document_uri': 'retrieval panel',
    'document_title': 'retrieval panel',
    'document_meta': 'retrieval panel',
    'order': 'retrieval panel',
    'doc_item_refs': 'retrieval panel',
    'page_numbers': 'retrieval panel',
    'headings': 'retrieval panel',
    'labels': 'retrieval panel',
  },
  'CodeExecutionEntry': {
    'code': 'executions panel',
    'stdout': 'executions panel',
    'stderr': 'executions panel',
    'success': 'executions panel',
    'search_calls': 'executions panel',
  },
  'CapabilityEvidenceRecord': {
    'occurrences': 'consulted-not-cited',
    'declaration': 'grounding indicator',
    'question': 'grounding indicator; recommend declining: compaction '
        'bookkeeping',
    'in_progress': 'grounding indicator; recommend declining: compaction '
        'bookkeeping',
    'latest_evidence_epoch': 'grounding indicator; recommend declining: '
        'compaction bookkeeping',
  },
  'EvidenceOccurrence': {
    'capability': 'consulted-not-cited',
    'chunk_id': 'consulted-not-cited',
    'retrieved_in_questions': 'consulted-not-cited',
    'cited_in_questions': 'consulted-not-cited',
  },
  'CitationDeclaration': {
    'question': 'grounding indicator',
    'epoch': 'grounding indicator',
    'refs': 'grounding indicator',
  },
  'EvidenceRef': {
    'capability': 'grounding indicator',
    'chunk_id': 'grounding indicator',
  },
};

/// Namespaces checked against another namespace's contract: `analysis`
/// (haiku.rag 0.84.0) carries `rag`'s fields, plus the `executions` log,
/// which 0.87.0 carries under `rag`.
const _sameFieldsAs = {'analysis': 'rag'};

/// Keys the frontend writes on send without reading them, with the normalised
/// schema type the value it writes must satisfy: `executions` is emptied by
/// `RagSnapshot.withEmptyRunScopedKeys`. Checked where present, since `rag` on
/// haiku.rag 0.84.0 has no `executions`.
const _written = <String, Map<String, String>>{
  'rag': {'executions': 'list[CodeExecutionEntry]'},
};

/// Required fields of each type the frontend parses whole, as its parser
/// requires them; a test below holds `Citation.fromJson` to this list.
const _parserRequired = {
  'Citation': {'chunk_id', 'content', 'document_id', 'document_uri'},
};

String _normalised(Map<String, dynamic> property) {
  final ref = property[r'$ref'];
  if (ref is String) return ref.split('/').last;
  final anyOf = property['anyOf'];
  if (anyOf is List) {
    return anyOf.map((m) => _normalised(m as Map<String, dynamic>)).join(' | ');
  }
  final type = property['type'];
  if (type == 'array') {
    final items = property['items'];
    final itemType = items is Map<String, dynamic> ? _normalised(items) : 'any';
    return 'list[$itemType]';
  }
  if (type == 'object') {
    final values = property['additionalProperties'];
    final valueType =
        values is Map<String, dynamic> ? _normalised(values) : 'any';
    return 'map[$valueType]';
  }
  return type is String ? type : 'any';
}

/// Every schema type in [features] with properties, by name: each namespace's
/// root under the namespace, each `$defs` entry under its own name.
Map<String, _Shape> _shapesOf(Map<String, dynamic> features) {
  final shapes = <String, _Shape>{};
  void add(String name, Map<String, dynamic> schema) {
    final properties = schema['properties'];
    if (properties is! Map<String, dynamic>) return;
    final shape = (
      properties: {
        for (final e in properties.entries)
          e.key: _normalised(e.value as Map<String, dynamic>),
      },
      required: {...((schema['required'] as List?) ?? const []).cast<String>()},
    );
    final existing = shapes[name];
    if (existing != null &&
        !(const DeepCollectionEquality().equals(
              existing.properties,
              shape.properties,
            ) &&
            const SetEquality<String>()
                .equals(existing.required, shape.required))) {
      throw StateError('Schema type $name differs between namespaces.');
    }
    shapes[name] = shape;
  }

  for (final entry in features.entries) {
    final schema = (entry.value as Map<String, dynamic>)['json_schema']
        as Map<String, dynamic>;
    add(entry.key, schema);
    final defs = (schema[r'$defs'] as Map<String, dynamic>?) ?? const {};
    for (final def in defs.entries) {
      add(def.key, def.value as Map<String, dynamic>);
    }
  }
  return shapes;
}

void main() {
  final files = Directory(_snapshotDir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final shapesByFile = {
    for (final file in files)
      file.uri.pathSegments.last: _shapesOf(
        (jsonDecode(file.readAsStringSync())
            as Map<String, dynamic>)['features'] as Map<String, dynamic>,
      ),
  };

  test('a snapshot exists for each supported haiku.rag version', () {
    expect(shapesByFile.keys, containsAll(_supportedSnapshots));
  });

  test('each supported snapshot carries the rag namespace', () {
    for (final name in _supportedSnapshots) {
      expect(shapesByFile[name]?.containsKey('rag'), isTrue, reason: name);
    }
  });

  test('no key is both read and unread', () {
    for (final type in _read.keys) {
      final both = _read[type]!
          .keys
          .toSet()
          .intersection((_unread[type] ?? const {}).keys.toSet());
      expect(both, isEmpty, reason: type);
    }
  });

  test('Citation.fromJson requires exactly the fields listed as required', () {
    final required = _parserRequired['Citation']!;
    final minimal = {for (final key in required) key: 'x'};
    expect(
      () => Citation.fromJson(minimal),
      returnsNormally,
      reason: 'the parser requires a field _parserRequired does not list',
    );
    for (final key in required) {
      expect(
        () => Citation.fromJson({...minimal}..remove(key)),
        throwsA(isA<MalformedResponseException>()),
        reason: '$key is listed as required but the parser does not require '
            'it',
      );
    }
  });

  test('every key in the table exists in a snapshot', () {
    for (final entry in [
      ..._read.entries,
      ..._unread.entries,
      ..._written.entries,
    ]) {
      for (final property in entry.value.keys) {
        final seen = shapesByFile.values.any(
          (shapes) => shapes.entries.any(
            (s) =>
                (_sameFieldsAs[s.key] ?? s.key) == entry.key &&
                s.value.properties.containsKey(property),
          ),
        );
        expect(
          seen,
          isTrue,
          reason: '${entry.key}.$property is in no snapshot; its reader and '
              'its table entry can go',
        );
      }
    }
  });

  for (final MapEntry(key: file, value: shapes) in shapesByFile.entries) {
    group(file, () {
      for (final MapEntry(key: type, value: shape) in shapes.entries) {
        final contractType = _sameFieldsAs[type] ?? type;

        test('$type: every property is read or unread', () {
          final read = _read[contractType] ?? const {};
          final unread = _unread[contractType] ?? const {};
          expect(
            _read.containsKey(contractType) ||
                _unread.containsKey(contractType),
            isTrue,
            reason: '$type is not in the contract table; add its keys to '
                '_read or _unread',
          );
          for (final property in shape.properties.keys) {
            expect(
              read.containsKey(property) || unread.containsKey(property),
              isTrue,
              reason: '$type.$property is new; add it to _read or _unread',
            );
          }
        });

        final read = _read[contractType];
        if (read != null) {
          test('$type: each read property has the type its parser expects', () {
            for (final MapEntry(key: property, value: expected)
                in read.entries) {
              final actual = shape.properties[property];
              if (actual == null) continue;
              expect(actual, expected, reason: '$type.$property');
            }
          });

          test('$type: every read property is present', () {
            for (final property in read.keys) {
              expect(
                shape.properties,
                contains(property),
                reason: '$type.$property is gone from $file; update its '
                    'reader and the table',
              );
            }
          });
        }

        final written = _written[contractType];
        if (written != null) {
          test('$type: each written property has the type the frontend writes',
              () {
            for (final MapEntry(key: property, value: expected)
                in written.entries) {
              final actual = shape.properties[property];
              if (actual == null) continue;
              expect(actual, expected, reason: '$type.$property');
            }
          });
        }

        final required = _parserRequired[contractType];
        if (required != null) {
          test('$type: required fields match the parser', () {
            expect(shape.required, required);
          });
        }
      }
    });
  }
}
