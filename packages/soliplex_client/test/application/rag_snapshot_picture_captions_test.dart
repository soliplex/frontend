import 'package:soliplex_client/src/application/rag_snapshot.dart';
import 'package:test/test.dart';

void main() {
  group('RagSnapshot.pictureCaption (0.42 shape)', () {
    final rag = {
      'citations': ['chunk-A'],
      'citation_index': {
        'chunk-A': {
          'chunk_id': 'chunk-A',
          'content': 'cites Fig 1',
          'document_id': 'doc-1',
          'document_uri': 'file:///doc-1.pdf',
          'picture_refs': ['#/pictures/0', '#/pictures/1'],
        },
      },
      'searches': {
        'q': [
          {
            'content': 'cites Fig 1',
            'score': 0.9,
            'document_id': 'doc-1',
            'image_data': {
              '#/pictures/0': 'aGVsbG8=',
              '#/pictures/1': 'd29ybGQ=',
            },
            'picture_captions': {'#/pictures/0': 'Figure 1: revenue'},
          },
        ],
      },
    };

    test('returns the caption for a captioned ref', () {
      final snap = RagSnapshot.fromJson(rag);
      expect(snap.pictureCaption('doc-1', '#/pictures/0'), 'Figure 1: revenue');
    });

    test('returns null for a ref with bytes but no caption', () {
      final snap = RagSnapshot.fromJson(rag);
      expect(snap.pictureCaption('doc-1', '#/pictures/1'), isNull);
    });

    test('returns null for the wrong document', () {
      final snap = RagSnapshot.fromJson(rag);
      expect(snap.pictureCaption('doc-2', '#/pictures/0'), isNull);
    });
  });
}
