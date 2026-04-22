// ignore_for_file: prefer_const_constructors

import 'dart:convert';

import 'package:soliplex_client/src/schema/agui_features/rag.dart';
import 'package:test/test.dart';

/// Contract tests for rag.dart generated types.
///
/// These tests document and enforce the API surface that consuming code depends
/// on. They will fail to compile if required fields are renamed or removed,
/// alerting us to update consuming code.
///
/// These are NOT tests of JSON parsing correctness (that's quicktype's job).
/// They are tests of the SHAPE of the API we consume.
void main() {
  group('Rag contract', () {
    group('fields matching backend RAGState', () {
      test('has all four backend fields', () {
        final rag = Rag();

        expect(rag.citationIndex, isNull);
        expect(rag.citations, isNull);
        expect(rag.documentFilter, isNull);
        expect(rag.searches, isNull);
      });

      test('can construct with all fields populated', () {
        final rag = Rag(
          citationIndex: {},
          citations: [],
          documentFilter: "id = 'abc'",
          searches: {},
        );

        expect(rag.citationIndex, isEmpty);
        expect(rag.citations, isEmpty);
        expect(rag.documentFilter, equals("id = 'abc'"));
        expect(rag.searches, isEmpty);
      });
    });

    group('fromJson parsing', () {
      test('parses minimal state (all fields absent)', () {
        final rag = Rag.fromJson(<String, dynamic>{});

        expect(rag.citationIndex, isEmpty);
        expect(rag.citations, isEmpty);
        expect(rag.documentFilter, isNull);
        expect(rag.searches, isNull);
      });

      test('parses full backend state', () {
        final json = {
          'citation_index': {
            'c1': {
              'chunk_id': 'c1',
              'content': 'text',
              'document_id': 'd1',
              'document_uri': 'uri',
            },
          },
          'citations': ['c1'],
          'document_filter': "id = 'abc'",
          'searches': {
            'query1': [
              {'content': 'result', 'score': 0.9},
            ],
          },
        };

        final rag = Rag.fromJson(json);
        expect(rag.citationIndex, hasLength(1));
        expect(rag.citations, equals(['c1']));
        expect(rag.documentFilter, equals("id = 'abc'"));
        expect(rag.searches, hasLength(1));
      });

      test('searches null guard — absent searches does not crash', () {
        // Backend omits searches in STATE_DELTA events.
        final json = {
          'citations': ['c1'],
        };

        final rag = Rag.fromJson(json);
        expect(rag.searches, isNull);
        expect(rag.citations, equals(['c1']));
      });

      test('ignores unknown keys without crashing', () {
        final json = <String, dynamic>{
          'legacy_field': <String, int>{},
          'session_context': {'summary': 'old'},
          'citations': ['c1'],
        };

        final rag = Rag.fromJson(json);
        expect(rag.citations, equals(['c1']));
      });
    });

    group('documentFilter field', () {
      test('documentFilter roundtrips through JSON', () {
        final original = Rag(documentFilter: "id = 'abc-123'");

        final json = original.toJson();
        expect(json['document_filter'], equals("id = 'abc-123'"));

        final decoded = Rag.fromJson(json);
        expect(decoded.documentFilter, equals("id = 'abc-123'"));
      });
    });

    group('roundtrip serialization', () {
      test('Rag survives JSON roundtrip', () {
        final original = Rag(
          citationIndex: {
            'c1': Citation(
              chunkId: 'c1',
              content: 'text',
              documentId: 'd1',
              documentUri: 'uri',
            ),
          },
          citations: ['c1'],
          documentFilter: 'filter',
          searches: {
            'q': [SearchResult(content: 'r', score: 0.9)],
          },
        );

        final jsonString = jsonEncode(original.toJson());
        final decoded =
            Rag.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);

        expect(decoded.citationIndex, hasLength(1));
        expect(decoded.citations, equals(['c1']));
        expect(decoded.documentFilter, equals('filter'));
        expect(decoded.searches, hasLength(1));
      });
    });
  });

  group('Citation contract', () {
    group('required constructor parameters', () {
      test('chunkId, content, documentId, documentUri are required', () {
        final citation = Citation(
          chunkId: 'chunk-123',
          content: 'content',
          documentId: 'doc-456',
          documentUri: 'https://example.com',
        );

        expect(citation.chunkId, equals('chunk-123'));
        expect(citation.content, equals('content'));
        expect(citation.documentId, equals('doc-456'));
        expect(citation.documentUri, equals('https://example.com'));
      });
    });

    group('optional fields', () {
      test('documentTitle, headings, index, pageNumbers default to null', () {
        final citation = Citation(
          chunkId: 'c1',
          content: 'content',
          documentId: 'd1',
          documentUri: 'uri',
        );

        expect(citation.documentTitle, isNull);
        expect(citation.headings, isNull);
        expect(citation.index, isNull);
        expect(citation.pageNumbers, isNull);
      });

      test('all optional fields can be provided', () {
        final citation = Citation(
          chunkId: 'c1',
          content: 'content',
          documentId: 'd1',
          documentUri: 'uri',
          documentTitle: 'Title',
          headings: ['Section 1'],
          index: 1,
          pageNumbers: [1, 2],
        );

        expect(citation.documentTitle, equals('Title'));
        expect(citation.headings, equals(['Section 1']));
        expect(citation.index, equals(1));
        expect(citation.pageNumbers, equals([1, 2]));
      });
    });

    group('JSON keys', () {
      test('snake_case keys match backend', () {
        final json = {
          'chunk_id': 'c1',
          'content': 'text',
          'document_id': 'd1',
          'document_uri': 'uri',
          'document_title': 'Title',
          'headings': ['H1'],
          'index': 5,
          'page_numbers': [1],
        };

        final citation = Citation.fromJson(json);
        expect(citation.chunkId, equals('c1'));
        expect(citation.documentTitle, equals('Title'));
        expect(citation.headings, equals(['H1']));
        expect(citation.index, equals(5));
        expect(citation.pageNumbers, equals([1]));
      });

      test('toJson produces expected keys', () {
        final citation = Citation(
          chunkId: 'c1',
          content: 'text',
          documentId: 'd1',
          documentUri: 'uri',
        );

        final json = citation.toJson();
        expect(json.containsKey('chunk_id'), isTrue);
        expect(json.containsKey('content'), isTrue);
        expect(json.containsKey('document_id'), isTrue);
        expect(json.containsKey('document_uri'), isTrue);
      });
    });

    group('roundtrip serialization', () {
      test('Citation survives JSON roundtrip', () {
        final original = Citation(
          chunkId: 'c1',
          content: 'content',
          documentId: 'd1',
          documentUri: 'https://example.com',
          documentTitle: 'Test Doc',
          index: 1,
          headings: ['Section 1'],
          pageNumbers: [1, 2],
        );

        final jsonString = jsonEncode(original.toJson());
        final decoded = Citation.fromJson(
          jsonDecode(jsonString) as Map<String, dynamic>,
        );

        expect(decoded.chunkId, equals(original.chunkId));
        expect(decoded.content, equals(original.content));
        expect(decoded.documentId, equals(original.documentId));
        expect(decoded.documentUri, equals(original.documentUri));
        expect(decoded.documentTitle, equals(original.documentTitle));
        expect(decoded.index, equals(original.index));
        expect(decoded.headings, equals(original.headings));
        expect(decoded.pageNumbers, equals(original.pageNumbers));
      });
    });
  });

  group('SearchResult contract', () {
    test('content and score are required; rest is optional', () {
      final result = SearchResult(content: 'found text', score: 0.85);

      expect(result.content, equals('found text'));
      expect(result.score, equals(0.85));
      expect(result.chunkId, isNull);
      expect(result.documentId, isNull);
      expect(result.documentUri, isNull);
      expect(result.documentTitle, isNull);
      expect(result.docItemRefs, isNull);
      expect(result.headings, isNull);
      expect(result.labels, isNull);
      expect(result.pageNumbers, isNull);
    });

    test('JSON keys match backend SearchResult', () {
      final json = {
        'content': 'text',
        'score': 0.9,
        'chunk_id': 'c1',
        'document_id': 'd1',
        'document_uri': 'uri',
        'document_title': 'Title',
        'doc_item_refs': ['ref1'],
        'headings': ['H1'],
        'labels': ['label1'],
        'page_numbers': [1, 2],
      };

      final result = SearchResult.fromJson(json);
      expect(result.chunkId, equals('c1'));
      expect(result.docItemRefs, equals(['ref1']));
      expect(result.labels, equals(['label1']));
      expect(result.pageNumbers, equals([1, 2]));
    });
  });
}
