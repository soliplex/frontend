import 'dart:convert';

import 'package:ag_ui/ag_ui.dart';
import 'package:soliplex_client/src/application/citation_extractor.dart';
import 'package:test/test.dart';

/// A `rag` namespace block plus the STATE_DELTA that carries it. The backend
/// re-emits the whole `rag` block on each skill invocation's delta, so the
/// delta's only op replaces `/rag`.
({Map<String, dynamic> state, StateDeltaEvent delta}) ragInvocation({
  required Map<String, Map<String, dynamic>> citationIndex,
  required List<String> citations,
  required Map<String, dynamic> searches,
}) {
  final block = <String, dynamic>{
    'citation_index': citationIndex,
    'citations': citations,
    'searches': searches,
  };
  return (
    state: {'rag': block},
    delta: StateDeltaEvent(
      delta: [
        {'op': 'add', 'path': '/rag', 'value': block},
      ],
    ),
  );
}

Map<String, dynamic> citation(
  String chunkId, {
  String documentId = 'doc-1',
  List<String>? pictureRefs,
}) =>
    {
      'chunk_id': chunkId,
      'content': 'Citation $chunkId',
      'document_id': documentId,
      'document_uri': 'https://example.com/$documentId.pdf',
      if (pictureRefs != null) 'picture_refs': pictureRefs,
    };

/// One retrieval row carrying an inline figure's base64 bytes.
Map<String, dynamic> figureSearch(
  String documentId,
  String ref,
  String base64Bytes, {
  String? caption,
}) =>
    {
      'q': [
        {
          'content': 'row',
          'document_id': documentId,
          'image_data': {ref: base64Bytes},
          if (caption != null) 'picture_captions': {ref: caption},
        },
      ],
    };

void main() {
  group('CitationExtractor figure accumulation across a turn', () {
    late CitationExtractor extractor;

    setUp(() {
      extractor = CitationExtractor();
    });

    test(
        'preserves an earlier invocation figure bytes after a later '
        'invocation wipes searches', () {
      // Invocation 1 cites chunk-1, whose figure bytes ride its searches.
      final inv1 = ragInvocation(
        citationIndex: {
          'chunk-1': citation('chunk-1', pictureRefs: ['#/pictures/0']),
        },
        citations: ['chunk-1'],
        searches: figureSearch(
          'doc-1',
          '#/pictures/0',
          'aGVsbG8=', // "hello"
          caption: 'Figure 1',
        ),
      );

      // Invocation 2 cites chunk-2 and REPLACES the rag block: citation_index
      // stays cumulative, but searches now holds only invocation 2's rows —
      // chunk-1's figure bytes are gone from the state.
      final inv2 = ragInvocation(
        citationIndex: {
          'chunk-1': citation('chunk-1', pictureRefs: ['#/pictures/0']),
          'chunk-2': citation('chunk-2', documentId: 'doc-2'),
        },
        citations: ['chunk-2'],
        searches: const {
          'q': [
            {'content': 'row', 'document_id': 'doc-2'},
          ],
        },
      );

      var turn = extractor.accumulate(
        const TurnCitations.empty(),
        inv1.state,
        inv1.delta,
      );
      turn = extractor.accumulate(turn, inv2.state, inv2.delta);

      // Resolve against the run's END state (invocation 2's), where
      // chunk-1's figure no longer exists in searches.
      final refs = extractor.resolve(turn, inv2.state);

      expect(refs.map((r) => r.chunkId), containsAll(['chunk-1', 'chunk-2']));
      final chunk1 = refs.firstWhere((r) => r.chunkId == 'chunk-1');
      expect(chunk1.figures, hasLength(1));
      expect(chunk1.figures.single.ref, '#/pictures/0');
      expect(chunk1.figures.single.bytes, utf8.encode('hello'));
      // The caption is unioned independently of the bytes and must survive too.
      expect(chunk1.figures.single.caption, 'Figure 1');
    });

    test('unions distinct figures cited by different invocations', () {
      // Both invocations retrieve a figure (for different documents). Neither
      // side of the union is empty, so this exercises the merge union itself,
      // not its empty short-circuits: both figures must resolve.
      final inv1 = ragInvocation(
        citationIndex: {
          'chunk-1': citation('chunk-1', pictureRefs: ['#/pictures/0']),
        },
        citations: ['chunk-1'],
        searches: figureSearch('doc-1', '#/pictures/0', 'aGVsbG8='), // "hello"
      );
      final inv2 = ragInvocation(
        citationIndex: {
          'chunk-1': citation('chunk-1', pictureRefs: ['#/pictures/0']),
          'chunk-2': citation(
            'chunk-2',
            documentId: 'doc-2',
            pictureRefs: ['#/pictures/0'],
          ),
        },
        citations: ['chunk-2'],
        searches: figureSearch('doc-2', '#/pictures/0', 'd29ybGQ='), // "world"
      );

      var turn = extractor.accumulate(
        const TurnCitations.empty(),
        inv1.state,
        inv1.delta,
      );
      turn = extractor.accumulate(turn, inv2.state, inv2.delta);
      final refs = extractor.resolve(turn, inv2.state);

      final chunk1 = refs.firstWhere((r) => r.chunkId == 'chunk-1');
      final chunk2 = refs.firstWhere((r) => r.chunkId == 'chunk-2');
      expect(chunk1.figures.single.bytes, utf8.encode('hello'));
      expect(chunk2.figures.single.bytes, utf8.encode('world'));
    });

    test('single-invocation run still resolves its figure (regression)', () {
      final inv = ragInvocation(
        citationIndex: {
          'chunk-1': citation('chunk-1', pictureRefs: ['#/pictures/0']),
        },
        citations: ['chunk-1'],
        searches: figureSearch('doc-1', '#/pictures/0', 'aGVsbG8='),
      );

      final turn = extractor.accumulate(
        const TurnCitations.empty(),
        inv.state,
        inv.delta,
      );
      final refs = extractor.resolve(turn, inv.state);

      expect(refs, hasLength(1));
      expect(refs.single.figures.single.bytes, utf8.encode('hello'));
    });

    test('resolves both figures of one citation fed by different invocations',
        () {
      // One citation (chunk-1) declares two picture refs, but each ref's bytes
      // arrive on a DIFFERENT invocation's searches: ref 0 on invocation 1,
      // ref 1 on invocation 2. The turn union must carry both so the single
      // citation resolves to two figures — exercising the per-ref figure loop
      // with more than one surviving ref, which no other test does.
      final inv1 = ragInvocation(
        citationIndex: {
          'chunk-1': citation(
            'chunk-1',
            pictureRefs: ['#/pictures/0', '#/pictures/1'],
          ),
        },
        citations: ['chunk-1'],
        searches: figureSearch('doc-1', '#/pictures/0', 'aGVsbG8='), // "hello"
      );
      final inv2 = ragInvocation(
        citationIndex: {
          'chunk-1': citation(
            'chunk-1',
            pictureRefs: ['#/pictures/0', '#/pictures/1'],
          ),
        },
        citations: ['chunk-1'],
        searches: figureSearch('doc-1', '#/pictures/1', 'd29ybGQ='), // "world"
      );

      var turn = extractor.accumulate(
        const TurnCitations.empty(),
        inv1.state,
        inv1.delta,
      );
      turn = extractor.accumulate(turn, inv2.state, inv2.delta);
      final refs = extractor.resolve(turn, inv2.state);

      final chunk1 = refs.firstWhere((r) => r.chunkId == 'chunk-1');
      expect(chunk1.figures, hasLength(2));
      final byRef = {for (final f in chunk1.figures) f.ref: f.bytes};
      expect(byRef['#/pictures/0'], utf8.encode('hello'));
      expect(byRef['#/pictures/1'], utf8.encode('world'));
    });
  });
}
