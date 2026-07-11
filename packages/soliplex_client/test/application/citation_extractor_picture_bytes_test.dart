import 'dart:convert';

import 'package:soliplex_client/src/application/citation_extractor.dart';
import 'package:test/test.dart';

void main() {
  test('bakes only stage-1 (bytes-present) picture refs into the reference',
      () {
    final current = {
      'rag': {
        'citations': ['chunk-A'],
        'citation_index': {
          'chunk-A': {
            'chunk_id': 'chunk-A',
            'content': 'cites Fig 1 and Fig 2',
            'document_id': 'doc-1',
            'document_uri': 'file:///doc-1.pdf',
            'doc_item_refs': ['#/pictures/0', '#/pictures/1'],
            'picture_refs': ['#/pictures/0', '#/pictures/1'],
          },
        },
        'searches': {
          'q': [
            {
              'content': 'cites Fig 1 and Fig 2',
              'score': 0.9,
              'document_id': 'doc-1',
              'doc_item_refs': ['#/pictures/0'],
              'image_data': {'#/pictures/0': 'aGVsbG8='}, // stage-1
            },
          ],
        },
      },
    };

    final refs = CitationExtractor().extractNew(const {}, current);

    expect(refs, hasLength(1));
    final ref = refs.single;
    // Ref strings still carry both; only stage-1 has bytes.
    expect(ref.pictureRefs, ['#/pictures/0', '#/pictures/1']);
    expect(ref.pictureBytes.keys, ['#/pictures/0']);
    expect(ref.pictureBytes['#/pictures/0'], utf8.encode('hello'));
  });
}
