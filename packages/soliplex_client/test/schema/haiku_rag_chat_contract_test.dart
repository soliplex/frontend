// ignore_for_file: prefer_const_constructors

import 'dart:convert';

import 'package:soliplex_client/src/schema/agui_features/haiku_rag_chat.dart';
import 'package:test/test.dart';

/// Contract tests for haiku_rag_chat.dart generated types.
///
/// These tests document and enforce the API surface that consuming code depends
/// on. They will fail to compile if required fields are renamed or removed,
/// alerting us to update consuming code.
///
/// These are NOT tests of JSON parsing correctness (that's quicktype's job).
/// They are tests of the SHAPE of the API we consume.
void main() {
  group('HaikuRagChat contract', () {
    group('fields required by CitationExtractor', () {
      test('citations field exists and returns List<Citation>?', () {
        // CitationExtractor accesses:
        //   final haikuRagChat = HaikuRagChat.fromJson(ragChat);
        //   final qaHistory = haikuRagChat.qaHistory ?? [];
        final ragChat = HaikuRagChat();

        // This access will fail to compile if the field is renamed or removed
        final citations = ragChat.citations;
        expect(citations, isNull);
      });

      test('can construct with empty citations', () {
        final ragChat = HaikuRagChat(citations: []);

        expect(ragChat.citations, isEmpty);
      });
    });

    group('citationsHistory field', () {
      test(
        'citationsHistory field exists and returns List<List<Citation>>?',
        () {
          final ragChat = HaikuRagChat();
          final history = ragChat.citationsHistory;
          expect(history, isNull);
        },
      );

      test('can construct with citations history', () {
        final ragChat = HaikuRagChat(
          citationsHistory: [
            [
              Citation(
                chunkId: 'c1',
                content: 'content',
                documentId: 'd1',
                documentUri: 'uri',
              ),
            ],
          ],
        );
        expect(ragChat.citationsHistory, hasLength(1));
        expect(ragChat.citationsHistory![0], hasLength(1));
      });

      test('parses citations_history from JSON', () {
        final json = {
          'citation_registry': <String, int>{},
          'citations_history': [
            [
              {
                'chunk_id': 'c1',
                'content': 'text',
                'document_id': 'd1',
                'document_uri': 'uri',
              },
            ],
            <Map<String, dynamic>>[],
          ],
        };

        final ragChat = HaikuRagChat.fromJson(json);
        expect(ragChat.citationsHistory, hasLength(2));
        expect(ragChat.citationsHistory![0], hasLength(1));
        expect(ragChat.citationsHistory![1], isEmpty);
      });

      test('citations_history roundtrips through JSON', () {
        final original = HaikuRagChat(
          citationRegistry: const {},
          citationsHistory: [
            [
              Citation(
                chunkId: 'c1',
                content: 'content',
                documentId: 'd1',
                documentUri: 'uri',
              ),
            ],
          ],
        );

        final json = original.toJson();
        final decoded = HaikuRagChat.fromJson(json);
        expect(decoded.citationsHistory, hasLength(1));
        expect(decoded.citationsHistory![0][0].chunkId, 'c1');
      });
    });

    group('JSON keys required for parsing', () {
      test('parses from RAG state format', () {
        // The generated fromJson requires citation_registry to be present.
        // The backend always sends it (even if empty).
        final json = {
          'citation_registry': <String, int>{},
          'citations': <Map<String, dynamic>>[],
        };

        final ragChat = HaikuRagChat.fromJson(json);
        expect(ragChat.citations, isEmpty);
      });

      test('citations key must exist as array', () {
        final json = {
          'citation_registry': <String, int>{},
          'citations': [
            {
              'chunk_id': 'c1',
              'content': 'text',
              'document_id': 'd1',
              'document_uri': 'uri',
            },
          ],
        };

        final ragChat = HaikuRagChat.fromJson(json);
        expect(ragChat.citations, hasLength(1));
      });

      test('citation_registry is required in fromJson', () {
        final json = <String, dynamic>{
          'citation_registry': <String, int>{'ref-1': 0},
        };

        final ragChat = HaikuRagChat.fromJson(json);
        expect(ragChat.citationRegistry, equals({'ref-1': 0}));
      });
    });
  });

  group('Citation contract', () {
    group('fields required by CitationsSection UI', () {
      // CitationsSection depends on these specific fields for display

      test('documentTitle is optional String for display header', () {
        // UI uses: citation.documentTitle ?? citation.documentUri
        final citation = Citation(
          chunkId: 'c1',
          content: 'content',
          documentId: 'd1',
          documentUri: 'https://example.com/doc',
        );

        // These accesses will fail to compile if renamed/removed
        final title = citation.documentTitle;
        expect(title, isNull);
      });

      test('documentUri is required String for fallback display', () {
        final citation = Citation(
          chunkId: 'c1',
          content: 'content',
          documentId: 'd1',
          documentUri: 'https://example.com/doc',
        );

        // UI uses documentUri as fallback when title is null
        final uri = citation.documentUri;
        expect(uri, isNotEmpty);
      });

      test('content is required String for snippet display', () {
        // UI shows: citation.content (in italic, max 2 lines)
        final citation = Citation(
          chunkId: 'c1',
          content: 'This is the citation content snippet',
          documentId: 'd1',
          documentUri: 'uri',
        );

        final content = citation.content;
        expect(content, contains('snippet'));
      });

      test('documentUri is used for "View source" link', () {
        // UI checks: _isValidUrl(citation.documentUri)
        // Then opens: citation.documentUri
        final citation = Citation(
          chunkId: 'c1',
          content: 'content',
          documentId: 'd1',
          documentUri: 'https://example.com/document.pdf',
        );

        final uri = Uri.tryParse(citation.documentUri);
        expect(uri, isNotNull);
        expect(uri!.scheme, anyOf('http', 'https'));
      });
    });

    group('required constructor parameters', () {
      test('chunkId is required', () {
        // This documents that chunkId cannot be omitted
        final citation = Citation(
          chunkId: 'chunk-123',
          content: 'content',
          documentId: 'doc-456',
          documentUri: 'uri',
        );

        expect(citation.chunkId, equals('chunk-123'));
      });

      test('content is required', () {
        final citation = Citation(
          chunkId: 'c1',
          content: 'required content',
          documentId: 'd1',
          documentUri: 'uri',
        );

        expect(citation.content, equals('required content'));
      });

      test('documentId is required', () {
        final citation = Citation(
          chunkId: 'c1',
          content: 'content',
          documentId: 'doc-id',
          documentUri: 'uri',
        );

        expect(citation.documentId, equals('doc-id'));
      });

      test('documentUri is required', () {
        final citation = Citation(
          chunkId: 'c1',
          content: 'content',
          documentId: 'd1',
          documentUri: 'https://example.com',
        );

        expect(citation.documentUri, equals('https://example.com'));
      });
    });

    group('optional fields the UI handles', () {
      test('documentTitle defaults to null', () {
        final citation = Citation(
          chunkId: 'c1',
          content: 'content',
          documentId: 'd1',
          documentUri: 'uri',
        );

        // UI displays documentUri when documentTitle is null
        expect(citation.documentTitle, isNull);
      });

      test('documentTitle can be provided', () {
        final citation = Citation(
          chunkId: 'c1',
          content: 'content',
          documentId: 'd1',
          documentUri: 'uri',
          documentTitle: 'My Document',
        );

        expect(citation.documentTitle, equals('My Document'));
      });

      test('index field exists for display ordering', () {
        final citation = Citation(
          chunkId: 'c1',
          content: 'content',
          documentId: 'd1',
          documentUri: 'uri',
          index: 1,
        );

        final index = citation.index;
        expect(index, equals(1));
      });

      test('headings field exists', () {
        final citation = Citation(
          chunkId: 'c1',
          content: 'content',
          documentId: 'd1',
          documentUri: 'uri',
          headings: ['Section 1', 'Subsection A'],
        );

        final headings = citation.headings;
        expect(headings, hasLength(2));
      });

      test('pageNumbers field exists', () {
        final citation = Citation(
          chunkId: 'c1',
          content: 'content',
          documentId: 'd1',
          documentUri: 'uri',
          pageNumbers: [1, 2, 3],
        );

        final pages = citation.pageNumbers;
        expect(pages, hasLength(3));
      });
    });

    group('JSON keys for parsing', () {
      test('required JSON keys match snake_case convention', () {
        // This documents the exact JSON keys the backend must provide
        final json = {
          'chunk_id': 'c1',
          'content': 'text',
          'document_id': 'd1',
          'document_uri': 'uri',
        };

        final citation = Citation.fromJson(json);
        expect(citation.chunkId, equals('c1'));
        expect(citation.content, equals('text'));
        expect(citation.documentId, equals('d1'));
        expect(citation.documentUri, equals('uri'));
      });

      test('optional JSON keys match snake_case convention', () {
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
          documentTitle: 'Title',
        );

        final json = citation.toJson();

        // These key names are part of the contract
        expect(json.containsKey('chunk_id'), isTrue);
        expect(json.containsKey('content'), isTrue);
        expect(json.containsKey('document_id'), isTrue);
        expect(json.containsKey('document_uri'), isTrue);
        expect(json.containsKey('document_title'), isTrue);
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

  group('QaResponse contract', () {
    group('fields that exist in the schema', () {
      test('answer is required String', () {
        final qa = QaResponse(answer: 'The answer', question: 'The question');

        final answer = qa.answer;
        expect(answer, equals('The answer'));
      });

      test('question is required String', () {
        final qa = QaResponse(answer: 'answer', question: 'What is X?');

        final question = qa.question;
        expect(question, equals('What is X?'));
      });

      test('citations is optional List<Citation>', () {
        final qa = QaResponse(
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
        );

        final citations = qa.citations;
        expect(citations, hasLength(1));
      });

      test('confidence is optional double', () {
        final qa = QaResponse(
          answer: 'answer',
          question: 'question',
          confidence: 0.95,
        );

        final confidence = qa.confidence;
        expect(confidence, equals(0.95));
      });
    });

    group('JSON keys for parsing', () {
      test('required JSON keys', () {
        final json = {'answer': 'The answer', 'question': 'The question'};

        final qa = QaResponse.fromJson(json);
        expect(qa.answer, equals('The answer'));
        expect(qa.question, equals('The question'));
      });
    });
  });

  group('SessionContext contract', () {
    test('lastUpdated is optional DateTime', () {
      final context = SessionContext(
        lastUpdated: DateTime(2024, 1, 15),
        summary: 'A summary',
      );

      final lastUpdated = context.lastUpdated;
      expect(lastUpdated, isNotNull);
    });

    test('summary is optional String', () {
      final context = SessionContext(summary: 'Context summary');

      final summary = context.summary;
      expect(summary, equals('Context summary'));
    });

    test('JSON keys for parsing', () {
      final json = {
        'last_updated': '2024-01-15T00:00:00.000',
        'summary': 'A summary',
      };

      final context = SessionContext.fromJson(json);
      expect(context.lastUpdated, isNotNull);
      expect(context.summary, equals('A summary'));
    });
  });
}
