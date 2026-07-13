import 'package:soliplex_client/src/application/citation_extractor.dart';
import 'package:test/test.dart';

void main() {
  group('CitationExtractor', () {
    late CitationExtractor extractor;

    setUp(() {
      extractor = CitationExtractor();
    });

    group('wire shape', () {
      Map<String, dynamic> createCitation({
        required String chunkId,
        String content = 'test content',
        String documentId = 'doc-1',
        String documentUri = 'https://example.com/doc.pdf',
        String? documentTitle,
        List<String>? headings,
        List<int>? pageNumbers,
        List<String>? pictureRefs,
        List<String>? chunkIds,
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
          if (pictureRefs != null) 'picture_refs': pictureRefs,
          if (chunkIds != null) 'chunk_ids': chunkIds,
          if (index != null) 'index': index,
        };
      }

      /// Builds a RAG-namespaced state. `citations` is a flat list of chunk
      /// ids cited during the current invocation; `citation_index` resolves
      /// each id to a full Citation.
      Map<String, dynamic> createState({
        Map<String, Map<String, dynamic>> citationIndex = const {},
        List<String> citations = const [],
      }) {
        return {
          'rag': {
            'citation_index': citationIndex,
            'citations': citations,
          },
        };
      }

      test('returns empty when no state change', () {
        final state = createState(
          citationIndex: {'c1': createCitation(chunkId: 'c1')},
          citations: ['c1'],
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

      test('extracts citations when previous is empty', () {
        final previous = createState();
        final current = createState(
          citationIndex: {
            'chunk-1': createCitation(
              chunkId: 'chunk-1',
              content: 'Citation content',
              documentTitle: 'Test Doc',
              headings: ['Chapter 1'],
              pageNumbers: [1, 2],
              pictureRefs: ['#/pictures/0', '#/pictures/1'],
              chunkIds: ['chunk-1', 'chunk-2'],
              index: 1,
            ),
          },
          citations: ['chunk-1'],
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
        // picture_refs without in-state bytes produce no figures.
        expect(refs[0].figures, isEmpty);
        expect(refs[0].chunkIds, ['chunk-1', 'chunk-2']);
        expect(refs[0].index, 1);
      });

      test('defaults headings and pageNumbers to empty lists when absent', () {
        final previous = createState();
        final current = createState(
          citationIndex: {'c1': createCitation(chunkId: 'c1')},
          citations: ['c1'],
        );

        final refs = extractor.extractNew(previous, current);

        expect(refs, hasLength(1));
        expect(refs[0].headings, isEmpty);
        expect(refs[0].pageNumbers, isEmpty);
      });

      test('extracts only ids not already in previous', () {
        final previous = createState(
          citationIndex: {'old-chunk': createCitation(chunkId: 'old-chunk')},
          citations: ['old-chunk'],
        );
        final current = createState(
          citationIndex: {
            'old-chunk': createCitation(chunkId: 'old-chunk'),
            'new-chunk': createCitation(chunkId: 'new-chunk'),
          },
          citations: ['old-chunk', 'new-chunk'],
        );

        final refs = extractor.extractNew(previous, current);

        expect(refs, hasLength(1));
        expect(refs[0].chunkId, 'new-chunk');
      });

      test('extracts new ids across invocation reset', () {
        // Prior invocation's citations are cleared by the lifespan hook;
        // the new invocation's ids should still be extracted even though
        // the previous snapshot held different ids.
        final previous = createState(
          citationIndex: {
            'a': createCitation(chunkId: 'a'),
            'b': createCitation(chunkId: 'b'),
          },
          citations: ['a', 'b'],
        );
        final current = createState(
          citationIndex: {
            'a': createCitation(chunkId: 'a'),
            'b': createCitation(chunkId: 'b'),
            'c': createCitation(chunkId: 'c'),
          },
          citations: ['c'],
        );

        final refs = extractor.extractNew(previous, current);

        expect(refs, hasLength(1));
        expect(refs[0].chunkId, 'c');
      });

      test('extracts multiple new ids at once', () {
        final previous = createState();
        final current = createState(
          citationIndex: {
            'chunk-1': createCitation(chunkId: 'chunk-1'),
            'chunk-2': createCitation(chunkId: 'chunk-2'),
            'chunk-3': createCitation(chunkId: 'chunk-3'),
          },
          citations: ['chunk-1', 'chunk-2', 'chunk-3'],
        );

        final refs = extractor.extractNew(previous, current);

        expect(refs, hasLength(3));
        expect(refs.map((r) => r.chunkId), ['chunk-1', 'chunk-2', 'chunk-3']);
      });

      test('returns empty when current has no citations', () {
        final previous = createState();
        final current = createState();

        final refs = extractor.extractNew(previous, current);

        expect(refs, isEmpty);
      });

      test('extracts citations from STATE_DELTA with minimal keys', () {
        final previous = createState();
        final current = <String, dynamic>{
          'rag': {
            'citation_index': {'c1': createCitation(chunkId: 'c1')},
            'citations': ['c1'],
          },
        };

        final refs = extractor.extractNew(previous, current);

        expect(refs, hasLength(1));
        expect(refs[0].chunkId, 'c1');
      });

      test('skips citation ids missing from citation_index', () {
        final previous = createState();
        final current = createState(
          citationIndex: {'c1': createCitation(chunkId: 'c1')},
          citations: ['c1', 'missing'],
        );

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

      test('returns empty when current citations are a subset of previous', () {
        // Happens when lifespan resets to empty mid-stream, or when ids from
        // previous are no longer present in current.
        final previous = <String, dynamic>{
          'rag': {
            'citation_index': <String, dynamic>{},
            'citations': ['a', 'b'],
          },
        };
        final current = <String, dynamic>{
          'rag': {
            'citation_index': <String, dynamic>{},
            'citations': ['a'],
          },
        };

        final refs = extractor.extractNew(previous, current);

        expect(refs, isEmpty);
      });

      test('returns empty when current citations are cleared', () {
        final previous = <String, dynamic>{};
        final current = <String, dynamic>{
          'rag': {
            'citation_index': <String, dynamic>{},
            'citations': <String>[],
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

      test('treats non-Map previous rag key as empty', () {
        final previous = <String, dynamic>{'rag': 42};
        final current = <String, dynamic>{
          'rag': {
            'citation_index': <String, dynamic>{},
            'citations': <String>[],
          },
        };

        // Previous coerced to empty; current has no citations either.
        final refs = extractor.extractNew(previous, current);
        expect(refs, isEmpty);
      });

      test('returns empty when citations is not a List', () {
        final previous = <String, dynamic>{};
        final current = <String, dynamic>{
          'rag': {'citations': 'not a list'},
        };

        final refs = extractor.extractNew(previous, current);
        expect(refs, isEmpty);
      });

      test(
        'tolerates non-string entries in the citations list',
        () {
          // citations is supposed to be List<String>. Any other shape
          // (ints, nulls, nested lists) must not crash the extractor.
          final previous = <String, dynamic>{};
          final current = <String, dynamic>{
            'rag': {
              'citation_index': <String, dynamic>{},
              'citations': <dynamic>[123, null, <String>[]],
            },
          };

          final refs = extractor.extractNew(previous, current);
          expect(refs, isEmpty);
        },
      );
    });
  });
}
