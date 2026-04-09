import 'package:soliplex_client/src/application/citation_extractor.dart';
import 'package:soliplex_client/src/schema/agui_features/rag.dart';
import 'package:test/test.dart';

void main() {
  group('CitationExtractor', () {
    late CitationExtractor extractor;

    setUp(() {
      extractor = CitationExtractor();
    });

    group('extractNew', () {
      Map<String, dynamic> createState({
        List<Map<String, dynamic>> qaHistory = const [],
      }) {
        return {
          'rag': {
            'qa_history': qaHistory,
            'citations': <Map<String, dynamic>>[],
          },
        };
      }

      Map<String, dynamic> createQaEntry({
        required String question,
        required String answer,
        List<Map<String, dynamic>> citations = const [],
      }) {
        return {'question': question, 'answer': answer, 'citations': citations};
      }

      Map<String, dynamic> createCitation({
        required String chunkId,
        String content = 'test content',
        String documentId = 'doc-1',
        String documentUri = 'https://example.com/doc.pdf',
        String? documentTitle,
        List<String>? headings,
        List<int>? pageNumbers,
        int? index,
      }) {
        return {
          'chunk_id': chunkId,
          'content': content,
          'document_id': documentId,
          'document_uri': documentUri,
          if (documentTitle != null) 'document_title': documentTitle,
          if (headings != null) 'headings': headings,
          if (pageNumbers != null) 'page_numbers': pageNumbers,
          if (index != null) 'index': index,
        };
      }

      test('returns empty when no state change', () {
        final state = createState(
          qaHistory: [
            createQaEntry(
              question: 'Q1',
              answer: 'A1',
              citations: [createCitation(chunkId: 'c1')],
            ),
          ],
        );

        final refs = extractor.extractNew(state, state);

        expect(refs, isEmpty);
      });

      test('returns empty when previous state is empty', () {
        final previous = createState();
        final current = createState();

        final refs = extractor.extractNew(previous, current);

        expect(refs, isEmpty);
      });

      test('extracts citations from new qa_history entry', () {
        final previous = createState();
        final current = createState(
          qaHistory: [
            createQaEntry(
              question: 'Q1',
              answer: 'A1',
              citations: [
                createCitation(
                  chunkId: 'chunk-1',
                  content: 'Citation content',
                  documentTitle: 'Test Doc',
                  headings: ['Chapter 1'],
                  pageNumbers: [1, 2],
                  index: 1,
                ),
              ],
            ),
          ],
        );

        final refs = extractor.extractNew(previous, current);

        expect(refs, hasLength(1));
        expect(refs[0].chunkId, 'chunk-1');
        expect(refs[0].content, 'Citation content');
        expect(refs[0].documentId, 'doc-1');
        expect(refs[0].documentUri, 'https://example.com/doc.pdf');
        expect(refs[0].documentTitle, 'Test Doc');
        expect(refs[0].headings, ['Chapter 1']);
        expect(refs[0].pageNumbers, [1, 2]);
        expect(refs[0].index, 1);
      });

      test('extracts only new entries when qa_history grows', () {
        final previous = createState(
          qaHistory: [
            createQaEntry(
              question: 'Q1',
              answer: 'A1',
              citations: [createCitation(chunkId: 'old-chunk')],
            ),
          ],
        );
        final current = createState(
          qaHistory: [
            createQaEntry(
              question: 'Q1',
              answer: 'A1',
              citations: [createCitation(chunkId: 'old-chunk')],
            ),
            createQaEntry(
              question: 'Q2',
              answer: 'A2',
              citations: [createCitation(chunkId: 'new-chunk')],
            ),
          ],
        );

        final refs = extractor.extractNew(previous, current);

        expect(refs, hasLength(1));
        expect(refs[0].chunkId, 'new-chunk');
      });

      test('extracts multiple citations from single new entry', () {
        final previous = createState();
        final current = createState(
          qaHistory: [
            createQaEntry(
              question: 'Q1',
              answer: 'A1',
              citations: [
                createCitation(chunkId: 'chunk-1'),
                createCitation(chunkId: 'chunk-2'),
                createCitation(chunkId: 'chunk-3'),
              ],
            ),
          ],
        );

        final refs = extractor.extractNew(previous, current);

        expect(refs, hasLength(3));
        expect(refs.map((r) => r.chunkId), ['chunk-1', 'chunk-2', 'chunk-3']);
      });

      test('handles entry with no citations', () {
        final previous = createState();
        final current = createState(
          qaHistory: [createQaEntry(question: 'Q1', answer: 'A1')],
        );

        final refs = extractor.extractNew(previous, current);

        expect(refs, isEmpty);
      });

      test('extracts citations from STATE_DELTA with minimal keys', () {
        final previous = createState();
        final current = <String, dynamic>{
          'rag': {
            'qa_history': [
              createQaEntry(
                question: 'Q1',
                answer: 'A1',
                citations: [createCitation(chunkId: 'c1')],
              ),
            ],
          },
        };

        final refs = extractor.extractNew(previous, current);

        expect(refs, hasLength(1));
        expect(refs[0].chunkId, 'c1');
      });
    });

    group('edge cases', () {
      test('returns empty for unknown state format', () {
        final previous = <String, dynamic>{};
        final current = <String, dynamic>{'unknown_key': <String, dynamic>{}};

        final refs = extractor.extractNew(previous, current);

        expect(refs, isEmpty);
      });

      test('returns empty when current has fewer entries than previous', () {
        // This can happen with FIFO rotation
        final previous = <String, dynamic>{
          'rag': {
            'qa_history': [
              {
                'question': 'Q1',
                'answer': 'A1',
                'citations': <Map<String, dynamic>>[],
              },
              {
                'question': 'Q2',
                'answer': 'A2',
                'citations': <Map<String, dynamic>>[],
              },
            ],
          },
        };
        final current = <String, dynamic>{
          'rag': {
            'qa_history': [
              {
                'question': 'Q2',
                'answer': 'A2',
                'citations': <Map<String, dynamic>>[],
              },
            ],
          },
        };

        final refs = extractor.extractNew(previous, current);

        expect(refs, isEmpty);
      });

      test('returns empty when new entry has no citations', () {
        final previous = <String, dynamic>{};
        final current = <String, dynamic>{
          'rag': {
            'qa_history': [
              {
                'question': 'Q1',
                'answer': 'A1',
                'citations': <Map<String, dynamic>>[],
              },
            ],
          },
        };

        final refs = extractor.extractNew(previous, current);
        expect(refs, isEmpty);
      });

      test('returns empty when rag key is not a Map', () {
        final previous = <String, dynamic>{};
        final current = <String, dynamic>{'rag': 'not a map'};

        final refs = extractor.extractNew(previous, current);
        expect(refs, isEmpty);
      });

      test('returns empty when previous rag key is not a Map', () {
        final previous = <String, dynamic>{'rag': 42};
        final current = <String, dynamic>{
          'rag': {
            'qa_history': [
              {
                'question': 'Q1',
                'answer': 'A1',
                'citations': <Map<String, dynamic>>[],
              },
            ],
          },
        };

        // Treats previous as empty (length 0), extracts from current
        final refs = extractor.extractNew(previous, current);
        expect(refs, isEmpty);
      });

      test('returns empty when qa_history is not a List', () {
        final previous = <String, dynamic>{};
        final current = <String, dynamic>{
          'rag': {'qa_history': 'not a list'},
        };

        // qa_history length treated as 0 for both, no growth detected
        final refs = extractor.extractNew(previous, current);
        expect(refs, isEmpty);
      });

      test('returns empty on malformed qa_history entry', () {
        final previous = <String, dynamic>{};
        final current = <String, dynamic>{
          'rag': {
            'qa_history': [
              {'question': 'Q1'},
            ],
          },
        };

        final refs = extractor.extractNew(previous, current);
        expect(refs, isEmpty);
      });
    });

    test('knownRagKeys matches Rag schema keys', () {
      final schemaKeys = Rag().toJson().keys.toSet();
      // _knownRagKeys is private; verify via ragStateKey-adjacent constant.
      // Rag.toJson() uses snake_case keys matching the backend schema.
      expect(
        schemaKeys,
        equals(knownRagKeys),
        reason: '_knownRagKeys must stay in sync with Rag schema fields',
      );
    });
  });
}
