import 'package:ag_ui/ag_ui.dart';
import 'package:soliplex_client/src/application/citation_extractor.dart';
import 'package:soliplex_client/src/application/rag_snapshot.dart';
import 'package:soliplex_client/src/domain/source_reference.dart';
import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:test/test.dart';

void main() {
  group('CitationExtractor', () {
    late CitationExtractor extractor;

    setUp(() {
      extractor = CitationExtractor();
    });

    /// A [TurnCitations] over [ids] with no figures — for resolve() cases that
    /// exercise id resolution against the index, not figure preservation.
    TurnCitations turnOf(Set<String> ids) =>
        TurnCitations(ids, const CitedFigures.empty());

    /// Resolves every id cited in [state] — the common case where the caller
    /// has no accumulated set and just wants what the state itself carries.
    List<SourceReference> extract(Map<String, dynamic> state) =>
        extractor.resolve(extractor.citationsInState(state), state);

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
        Map<String, dynamic>? documentMeta,
      }) {
        return {
          'chunk_id': chunkId,
          'content': content,
          'document_id': documentId,
          'document_uri': documentUri,
          if (documentMeta != null) 'document_meta': documentMeta,
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

      test('resolves empty when the state has no citations', () {
        final refs = extract(createState());

        expect(refs, isEmpty);
      });

      test('resolves a citation with all its fields', () {
        final state = createState(
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

        final refs = extract(state);

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

      test('reads sourceUrl from the citation document_meta', () {
        final state = createState(
          citationIndex: {
            'c1': createCitation(
              chunkId: 'c1',
              documentMeta: {'source_url': 'https://example.test/a/view'},
            ),
          },
          citations: ['c1'],
        );

        final refs = extract(state);

        expect(refs.single.sourceUrl, Uri.parse('https://example.test/a/view'));
      });

      test('sourceUrl is null when document_meta carries no usable url', () {
        final state = createState(
          citationIndex: {
            'c1': createCitation(
              chunkId: 'c1',
              documentMeta: {'source_url': 'file:///x/a.pdf'},
            ),
            'c2': createCitation(chunkId: 'c2'),
          },
          citations: ['c1', 'c2'],
        );

        final refs = extract(state);

        expect(refs.every((r) => r.sourceUrl == null), isTrue);
      });

      test('defaults headings and pageNumbers to empty lists when absent', () {
        final state = createState(
          citationIndex: {'c1': createCitation(chunkId: 'c1')},
          citations: ['c1'],
        );

        final refs = extract(state);

        expect(refs, hasLength(1));
        expect(refs[0].headings, isEmpty);
        expect(refs[0].pageNumbers, isEmpty);
      });

      test('resolves a re-cited id — no subtraction of prior ids', () {
        // A chunk cited in an earlier turn is still resolved when re-cited.
        // The extractor never subtracts; cross-turn accumulation is the
        // caller's job.
        final state = createState(
          citationIndex: {
            'old-chunk': createCitation(chunkId: 'old-chunk'),
            'new-chunk': createCitation(chunkId: 'new-chunk'),
          },
          citations: ['old-chunk', 'new-chunk'],
        );

        final refs = extract(state);

        expect(
          refs.map((r) => r.chunkId),
          unorderedEquals(['old-chunk', 'new-chunk']),
        );
      });

      test('resolves accumulated ids absent from the current citations list',
          () {
        // The backend clears `citations` per invocation but keeps
        // `citation_index` session-cumulative. The caller hands resolve() the
        // full accumulated set; every id still resolves against the index even
        // though `citations` holds only the last invocation's id.
        final state = createState(
          citationIndex: {
            'a': createCitation(chunkId: 'a'),
            'b': createCitation(chunkId: 'b'),
            'c': createCitation(chunkId: 'c'),
          },
          citations: ['c'],
        );

        final refs = extractor.resolve(turnOf({'a', 'b', 'c'}), state);

        expect(refs.map((r) => r.chunkId), unorderedEquals(['a', 'b', 'c']));
      });

      test('resolves multiple ids at once', () {
        final state = createState(
          citationIndex: {
            'chunk-1': createCitation(chunkId: 'chunk-1'),
            'chunk-2': createCitation(chunkId: 'chunk-2'),
            'chunk-3': createCitation(chunkId: 'chunk-3'),
          },
          citations: ['chunk-1', 'chunk-2', 'chunk-3'],
        );

        final refs = extract(state);

        expect(
          refs.map((r) => r.chunkId),
          unorderedEquals(['chunk-1', 'chunk-2', 'chunk-3']),
        );
      });

      test('resolves against a minimally-shaped rag block', () {
        final state = <String, dynamic>{
          'rag': {
            'citation_index': {'c1': createCitation(chunkId: 'c1')},
            'citations': ['c1'],
          },
        };

        final refs = extract(state);

        expect(refs, hasLength(1));
        expect(refs[0].chunkId, 'c1');
      });

      test('skips citation ids missing from citation_index', () {
        final state = createState(
          citationIndex: {'c1': createCitation(chunkId: 'c1')},
          citations: ['c1', 'missing'],
        );

        final refs = extract(state);

        expect(refs, hasLength(1));
        expect(refs[0].chunkId, 'c1');
      });
    });

    group('citationIds', () {
      Map<String, dynamic> citation(String chunkId) => {
            'chunk_id': chunkId,
            'content': 'content for $chunkId',
            'document_id': 'doc-1',
            'document_uri': 'https://example.com/doc.pdf',
          };

      Map<String, dynamic> block(List<String> citations) => {
            'citation_index': {for (final id in citations) id: citation(id)},
            'citations': citations,
          };

      test('unions ids across every citation-bearing namespace', () {
        final state = <String, dynamic>{
          'rag': block(const ['a', 'b']),
          'analysis': block(const ['b', 'c']),
        };

        expect(extractor.citationsInState(state).ids, {'a', 'b', 'c'});
      });

      test('skips namespaces without a citation_index', () {
        final state = <String, dynamic>{
          'rag': block(const ['a']),
          'bubble-sandbox': {'foo': 'bar'},
        };

        expect(extractor.citationsInState(state).ids, {'a'});
      });

      test('tolerates a malformed citations list', () {
        final state = <String, dynamic>{
          'rag': {
            'citation_index': <String, dynamic>{},
            'citations': 'not a list',
          },
        };

        expect(extractor.citationsInState(state).ids, isEmpty);
      });

      test('is empty when the state has no citation namespaces', () {
        expect(extractor.citationsInState(const {'unknown': 42}).ids, isEmpty);
      });
    });

    group('accumulate (delta scoping)', () {
      Map<String, dynamic> citation(String chunkId) => {
            'chunk_id': chunkId,
            'content': 'content for $chunkId',
            'document_id': 'doc-1',
            'document_uri': 'https://example.com/doc.pdf',
          };

      Map<String, dynamic> block(List<String> citations) => {
            'citation_index': {for (final id in citations) id: citation(id)},
            'citations': citations,
          };

      StateDeltaEvent deltaTouching(List<String> paths) => StateDeltaEvent(
            delta: [
              for (final path in paths)
                {'op': 'add', 'path': path, 'value': 'x'},
            ],
          );

      test(
          'scopes to the namespace the delta touched, ignoring a stale '
          'sibling', () {
        // rag carries a prior turn's citations that ride the rebase snapshot;
        // this delta invoked only analysis, so rag's ids are not this turn's.
        final state = <String, dynamic>{
          'rag': block(const ['a']),
          'analysis': block(const ['b']),
        };

        final turn = extractor.accumulate(
          const TurnCitations.empty(),
          state,
          deltaTouching(const ['/analysis/citations/-']),
        );

        expect(turn.ids, {'b'});
      });

      test('unions across every namespace the delta touched', () {
        final state = <String, dynamic>{
          'rag': block(const ['a']),
          'analysis': block(const ['b']),
        };

        final turn = extractor.accumulate(
          const TurnCitations.empty(),
          state,
          deltaTouching(const ['/rag/citations/0', '/analysis/citations/0']),
        );

        expect(turn.ids, {'a', 'b'});
      });

      test('is empty when the delta touches no citation-bearing namespace', () {
        final state = <String, dynamic>{
          'rag': block(const ['a']),
        };

        final turn = extractor.accumulate(
          const TurnCitations.empty(),
          state,
          deltaTouching(const ['/document_filter']),
        );

        expect(turn.ids, isEmpty);
      });

      test('skips malformed ops with a warning', () {
        // A non-Map op and a pathless op are both malformed JSON-Patch. They
        // must be skipped (touching no namespace) and each logged, so a
        // drifting wire shape can't lose a namespace's citations silently.
        final sink = _RecordingSink();
        LogManager.instance.addSink(sink);
        addTearDown(() => LogManager.instance.removeSink(sink));

        // State is never read: malformed ops touch no namespace, so
        // accumulate returns before consulting it.
        final turn = extractor.accumulate(
          const TurnCitations.empty(),
          const {},
          const StateDeltaEvent(
            delta: [
              'not-a-map',
              <String, dynamic>{'op': 'add', 'value': 'x'},
            ],
          ),
        );

        expect(turn.ids, isEmpty);
        expect(sink.records, hasLength(2));
        expect(sink.records.every((r) => r.level == LogLevel.warning), isTrue);
      });

      test('skips a rooted op that names no namespace, with a warning', () {
        // A valid String path that yields no namespace segment ("/", "") is
        // degenerate JSON-Patch. Like the other malformed shapes it must be
        // skipped and logged, not silently dropped.
        final sink = _RecordingSink();
        LogManager.instance.addSink(sink);
        addTearDown(() => LogManager.instance.removeSink(sink));

        final turn = extractor.accumulate(
          const TurnCitations.empty(),
          const {},
          deltaTouching(const ['/']),
        );

        expect(turn.ids, isEmpty);
        expect(sink.records, hasLength(1));
        expect(sink.records.single.level, LogLevel.warning);
      });
    });

    group('resolve', () {
      Map<String, dynamic> citation(String chunkId) => {
            'chunk_id': chunkId,
            'content': 'content for $chunkId',
            'document_id': 'doc-1',
            'document_uri': 'https://example.com/doc.pdf',
          };

      Map<String, dynamic> stateWith(List<String> ids) => {
            'rag': {
              'citation_index': {for (final id in ids) id: citation(id)},
              'citations': ids,
            },
          };

      test('skips ids absent from every citation_index', () {
        final refs =
            extractor.resolve(turnOf({'a', 'ghost'}), stateWith(['a']));

        expect(refs.map((r) => r.chunkId), ['a']);
      });

      test('warns when a cited id is absent from every citation_index', () {
        // A cited id missing from the cumulative index means the source list
        // is silently short — a backend contract violation the caller can't
        // otherwise see. It must be logged.
        final sink = _RecordingSink();
        LogManager.instance.addSink(sink);
        addTearDown(() => LogManager.instance.removeSink(sink));

        extractor.resolve(turnOf({'a', 'ghost'}), stateWith(['a']));

        expect(sink.records, hasLength(1));
        expect(sink.records.single.level, LogLevel.warning);
        expect(sink.records.single.message, contains('ghost'));
      });

      test('is empty when the state carries no citation namespace', () {
        final refs = extractor.resolve(turnOf({'a'}), const {'unknown': 42});

        expect(refs, isEmpty);
      });
    });

    group('edge cases', () {
      test('resolves empty for unknown state format', () {
        final refs = extract(
          <String, dynamic>{'unknown_key': <String, dynamic>{}},
        );

        expect(refs, isEmpty);
      });

      test('resolves empty when the citations list is empty', () {
        final refs = extract(<String, dynamic>{
          'rag': {
            'citation_index': <String, dynamic>{},
            'citations': <String>[],
          },
        });

        expect(refs, isEmpty);
      });

      test('resolves empty when rag key is not a Map', () {
        final refs = extract(<String, dynamic>{'rag': 'not a map'});

        expect(refs, isEmpty);
      });

      test('resolves empty when citations is not a List', () {
        final refs = extract(<String, dynamic>{
          'rag': {'citations': 'not a list'},
        });

        expect(refs, isEmpty);
      });

      test('tolerates non-string entries in the citations list', () {
        // citations is supposed to be List<String>. Any other shape
        // (ints, nulls, nested lists) must not crash the extractor.
        final refs = extract(<String, dynamic>{
          'rag': {
            'citation_index': <String, dynamic>{},
            'citations': <dynamic>[123, null, <String>[]],
          },
        });

        expect(refs, isEmpty);
      });
    });

    group('multiple namespaces', () {
      Map<String, dynamic> citation(String chunkId) => {
            'chunk_id': chunkId,
            'content': 'content for $chunkId',
            'document_id': 'doc-1',
            'document_uri': 'https://example.com/doc.pdf',
          };

      Map<String, dynamic> block(List<String> citations) => {
            'citation_index': {for (final id in citations) id: citation(id)},
            'citations': citations,
          };

      test('resolves citations from the analysis namespace', () {
        final state = <String, dynamic>{
          'analysis': block(const ['a1']),
        };

        final refs = extract(state);

        expect(refs, hasLength(1));
        expect(refs.single.chunkId, 'a1');
      });

      test('deduplicates a chunk cited in both rag and analysis', () {
        final state = <String, dynamic>{
          'rag': block(const ['shared']),
          'analysis': block(const ['shared', 'analysis-only']),
        };

        final refs = extract(state);

        expect(
          refs.map((r) => r.chunkId),
          unorderedEquals(['shared', 'analysis-only']),
        );
      });
    });
  });
}

/// Captures records from the citation extractor's logger, ignoring all other
/// log traffic the singleton sees so assertions stay strict.
class _RecordingSink implements LogSink {
  final List<LogRecord> records = [];

  @override
  void write(LogRecord record) {
    if (record.loggerName == 'soliplex_client.citation_extractor') {
      records.add(record);
    }
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}
