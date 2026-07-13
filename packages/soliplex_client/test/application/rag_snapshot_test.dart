import 'package:soliplex_client/src/application/rag_snapshot.dart';
import 'package:test/test.dart';

void main() {
  group('RagSnapshot behavior', () {
    test('citationIds returns the raw string list', () {
      final json = {
        'citation_index': {
          'a': {
            'chunk_id': 'a',
            'content': 't',
            'document_id': 'd',
            'document_uri': 'u',
          },
          'b': {
            'chunk_id': 'b',
            'content': 't',
            'document_id': 'd',
            'document_uri': 'u',
          },
        },
        'citations': ['a', 'b'],
      };
      final snapshot = RagSnapshot.fromJson(json);
      expect(snapshot.citationIds, equals(['a', 'b']));
    });

    test('resolveCitation looks up via citation_index', () {
      final json = {
        'citation_index': {
          'a': {
            'chunk_id': 'a',
            'content': 'content-a',
            'document_id': 'd1',
            'document_uri': 'uri-a',
          },
        },
        'citations': ['a'],
      };
      final snapshot = RagSnapshot.fromJson(json);
      final citation = snapshot.resolveCitation('a');
      expect(citation, isNotNull);
      expect(citation!.content, equals('content-a'));
    });

    test('resolveCitation returns null for ids not in citation_index', () {
      final json = {
        'citation_index': <String, dynamic>{},
        'citations': ['orphan'],
      };
      final snapshot = RagSnapshot.fromJson(json);
      expect(snapshot.resolveCitation('orphan'), isNull);
    });

    test('empty state yields empty citationIds and null resolve', () {
      final snapshot = RagSnapshot.fromJson(<String, dynamic>{});
      expect(snapshot.citationIds, isEmpty);
      expect(snapshot.resolveCitation('any'), isNull);
    });

    test('tolerates non-String entries in citations', () {
      // One bad entry must not drop the whole snapshot.
      final json = <String, dynamic>{
        'citation_index': {
          'c1': {
            'chunk_id': 'c1',
            'content': 't',
            'document_id': 'd',
            'document_uri': 'u',
          },
          'c2': {
            'chunk_id': 'c2',
            'content': 't',
            'document_id': 'd',
            'document_uri': 'u',
          },
        },
        'citations': <dynamic>['c1', null, 42, 'c2'],
      };
      final snapshot = RagSnapshot.fromJson(json);
      expect(snapshot.citationIds, equals(['c1', 'c2']));
      expect(snapshot.resolveCitation('c1'), isNotNull);
      expect(snapshot.resolveCitation('c2'), isNotNull);
    });

    test('tolerates malformed citation_index entries', () {
      // One valid entry, one non-Map, one missing required field.
      final json = <String, dynamic>{
        'citation_index': <String, dynamic>{
          'c1': {
            'chunk_id': 'c1',
            'content': 't',
            'document_id': 'd',
            'document_uri': 'u',
          },
          'c2': 'not a map',
          'c3': {'chunk_id': 'c3'}, // missing required fields
        },
        'citations': ['c1', 'c2', 'c3'],
      };
      final snapshot = RagSnapshot.fromJson(json);
      expect(snapshot.citationIds, equals(['c1', 'c2', 'c3']));
      expect(snapshot.resolveCitation('c1'), isNotNull);
      expect(snapshot.resolveCitation('c2'), isNull);
      expect(snapshot.resolveCitation('c3'), isNull);
    });
  });

  group('buildRagDocumentFilterOverlay', () {
    test('wraps a filter string under rag.document_filter', () {
      final overlay = buildRagDocumentFilterOverlay("id = 'abc'");
      expect(
        overlay,
        equals({
          'rag': {'document_filter': "id = 'abc'"},
        }),
      );
    });

    test('carries null filter through (signals "clear")', () {
      final overlay = buildRagDocumentFilterOverlay(null);
      expect(
        overlay,
        equals({
          'rag': {'document_filter': null},
        }),
      );
    });

    test('only touches rag.document_filter, no other rag fields', () {
      final overlay = buildRagDocumentFilterOverlay('x');
      final rag = overlay['rag'] as Map<String, dynamic>;
      expect(rag.keys, equals(['document_filter']));
    });
  });
}
