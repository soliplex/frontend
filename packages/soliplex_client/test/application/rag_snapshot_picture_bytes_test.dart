import 'dart:convert';

import 'package:soliplex_client/src/application/rag_snapshot.dart';
import 'package:test/test.dart';

void main() {
  group('RagSnapshot.pictureBytes (0.42 shape)', () {
    final rag = {
      'citations': ['chunk-A'],
      'citation_index': {
        'chunk-A': {
          'chunk_id': 'chunk-A',
          'content': 'cites Fig 1',
          'document_id': 'doc-1',
          'document_uri': 'file:///doc-1.pdf',
          'doc_item_refs': ['#/texts/24', '#/pictures/0', '#/pictures/1'],
          'picture_refs': ['#/pictures/0', '#/pictures/1'],
        },
      },
      'searches': {
        'my query': [
          {
            'content': 'cites Fig 1',
            'score': 0.9,
            'document_id': 'doc-1',
            'doc_item_refs': ['#/texts/24', '#/pictures/0'],
            'image_data': {'#/pictures/0': 'aGVsbG8='}, // "hello"
          },
        ],
      },
    };

    test('returns decoded bytes for a stage-1 ref', () {
      final snap = RagSnapshot.fromJson(rag);
      expect(snap.pictureBytes('doc-1', '#/pictures/0'), utf8.encode('hello'));
    });

    test('returns null for a stage-2 ref (ref present, no bytes)', () {
      final snap = RagSnapshot.fromJson(rag);
      expect(snap.pictureBytes('doc-1', '#/pictures/1'), isNull);
    });

    test('returns null for the wrong document', () {
      final snap = RagSnapshot.fromJson(rag);
      expect(snap.pictureBytes('doc-2', '#/pictures/0'), isNull);
    });

    test('returns null for an undecodable base64 image_data value', () {
      final bad = Map<String, dynamic>.from(rag);
      bad['searches'] = {
        'q': [
          {
            'content': 'x',
            'score': 0.1,
            'document_id': 'doc-1',
            'image_data': {'#/pictures/0': '%%%not-base64%%%'},
          },
        ],
      };
      final snap = RagSnapshot.fromJson(bad);
      expect(snap.pictureBytes('doc-1', '#/pictures/0'), isNull);
    });

    test('skips a malformed search entry without throwing', () {
      final bad = Map<String, dynamic>.from(rag);
      bad['searches'] = {
        'q': [
          'not-a-map',
          {
            'content': 'x',
            'score': 0.1,
            'document_id': 'doc-1',
            'image_data': {'#/pictures/9': 'd29ybGQ='},
          },
        ],
      };
      final snap = RagSnapshot.fromJson(bad);
      expect(snap.pictureBytes('doc-1', '#/pictures/9'), utf8.encode('world'));
    });
  });
}
