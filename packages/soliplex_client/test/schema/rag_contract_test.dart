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
      test('has all six backend fields', () {
        final rag = Rag();

        // All fields from backend RAGState — compile-time check
        expect(rag.citations, isNull);
        expect(rag.documentFilter, isNull);
        expect(rag.documents, isNull);
        expect(rag.qaHistory, isNull);
        expect(rag.reports, isNull);
        expect(rag.searches, isNull);
      });

      test('can construct with all fields populated', () {
        final rag = Rag(
          citations: [],
          documentFilter: "id = 'abc'",
          documents: [],
          qaHistory: [],
          reports: [],
          searches: {},
        );

        expect(rag.citations, isEmpty);
        expect(rag.documentFilter, equals("id = 'abc'"));
        expect(rag.documents, isEmpty);
        expect(rag.qaHistory, isEmpty);
        expect(rag.reports, isEmpty);
        expect(rag.searches, isEmpty);
      });
    });

    group('fromJson parsing', () {
      test('parses minimal state (all fields absent)', () {
        final rag = Rag.fromJson(<String, dynamic>{});

        expect(rag.citations, isEmpty);
        expect(rag.documentFilter, isNull);
        expect(rag.documents, isEmpty);
        expect(rag.qaHistory, isEmpty);
        expect(rag.reports, isEmpty);
        expect(rag.searches, isNull);
      });

      test('parses full backend state', () {
        final json = {
          'citations': [
            {
              'chunk_id': 'c1',
              'content': 'text',
              'document_id': 'd1',
              'document_uri': 'uri',
            },
          ],
          'document_filter': "id = 'abc'",
          'documents': [
            {'created': '2026-01-01', 'title': 'Doc', 'uri': 'uri'},
          ],
          'qa_history': [
            {'question': 'Q', 'answer': 'A'},
          ],
          'reports': [
            {
              'question': 'Q',
              'title': 'Report',
              'executive_summary': 'Summary',
            },
          ],
          'searches': {
            'query1': [
              {'content': 'result', 'score': 0.9},
            ],
          },
        };

        final rag = Rag.fromJson(json);
        expect(rag.citations, hasLength(1));
        expect(rag.documentFilter, equals("id = 'abc'"));
        expect(rag.documents, hasLength(1));
        expect(rag.qaHistory, hasLength(1));
        expect(rag.reports, hasLength(1));
        expect(rag.searches, hasLength(1));
      });

      test('searches null guard — absent searches does not crash', () {
        // Backend omits searches in STATE_DELTA events.
        final json = {
          'qa_history': [
            {'question': 'Q', 'answer': 'A'},
          ],
        };

        final rag = Rag.fromJson(json);
        expect(rag.searches, isNull);
        expect(rag.qaHistory, hasLength(1));
      });

      test('ignores unknown keys without crashing', () {
        final json = <String, dynamic>{
          'citation_registry': <String, int>{},
          'session_context': {'summary': 'old'},
          'qa_history': [
            {'question': 'Q', 'answer': 'A'},
          ],
        };

        final rag = Rag.fromJson(json);
        expect(rag.qaHistory, hasLength(1));
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
          citations: [
            Citation(
              chunkId: 'c1',
              content: 'text',
              documentId: 'd1',
              documentUri: 'uri',
            ),
          ],
          documentFilter: 'filter',
          documents: [
            DocumentInfo(created: '2026-01-01', title: 'Doc', uri: 'uri'),
          ],
          qaHistory: [
            QaHistoryEntry(question: 'Q', answer: 'A'),
          ],
          reports: [
            ResearchEntry(
              question: 'Q',
              title: 'T',
              executiveSummary: 'S',
            ),
          ],
          searches: {
            'q': [SearchResult(content: 'r', score: 0.9)],
          },
        );

        final jsonString = jsonEncode(original.toJson());
        final decoded =
            Rag.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);

        expect(decoded.citations, hasLength(1));
        expect(decoded.documentFilter, equals('filter'));
        expect(decoded.documents, hasLength(1));
        expect(decoded.qaHistory, hasLength(1));
        expect(decoded.reports, hasLength(1));
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

  group('QaHistoryEntry contract', () {
    test('answer and question are required', () {
      final entry = QaHistoryEntry(answer: 'The answer', question: 'Q?');

      expect(entry.answer, equals('The answer'));
      expect(entry.question, equals('Q?'));
    });

    test('citations and confidence are optional', () {
      final entry = QaHistoryEntry(
        answer: 'answer',
        question: 'question',
        citations: [
          Citation(
            chunkId: 'c1',
            content: 'content',
            documentId: 'd1',
            documentUri: 'uri',
          ),
        ],
        confidence: 0.95,
      );

      expect(entry.citations, hasLength(1));
      expect(entry.confidence, equals(0.95));
    });

    test('JSON keys match backend QAHistoryEntry', () {
      final json = {'answer': 'A', 'question': 'Q', 'confidence': 0.9};

      final entry = QaHistoryEntry.fromJson(json);
      expect(entry.answer, equals('A'));
      expect(entry.question, equals('Q'));
      expect(entry.confidence, equals(0.9));
    });
  });

  group('DocumentInfo contract', () {
    test('created, title, uri are required; id is optional', () {
      final doc = DocumentInfo(
        created: '2026-01-01',
        title: 'Test Doc',
        uri: 'https://example.com/doc.pdf',
      );

      expect(doc.created, equals('2026-01-01'));
      expect(doc.title, equals('Test Doc'));
      expect(doc.uri, equals('https://example.com/doc.pdf'));
      expect(doc.id, isNull);
    });

    test('JSON keys match backend DocumentInfo', () {
      final json = {
        'created': '2026-01-01',
        'id': 'doc-123',
        'title': 'Doc',
        'uri': 'uri',
      };

      final doc = DocumentInfo.fromJson(json);
      expect(doc.id, equals('doc-123'));
    });
  });

  group('ResearchEntry contract', () {
    test('question, title, executiveSummary are required', () {
      final entry = ResearchEntry(
        question: 'What is X?',
        title: 'Research on X',
        executiveSummary: 'X is Y.',
      );

      expect(entry.question, equals('What is X?'));
      expect(entry.title, equals('Research on X'));
      expect(entry.executiveSummary, equals('X is Y.'));
    });

    test('JSON key is executive_summary (snake_case)', () {
      final json = {
        'question': 'Q',
        'title': 'T',
        'executive_summary': 'S',
      };

      final entry = ResearchEntry.fromJson(json);
      expect(entry.executiveSummary, equals('S'));

      final output = entry.toJson();
      expect(output.containsKey('executive_summary'), isTrue);
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
