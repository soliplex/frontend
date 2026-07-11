import 'package:soliplex_client/src/schema/agui_features/rag.dart';
import 'package:test/test.dart';

void main() {
  group('SearchResult.imageData', () {
    test('parses image_data from JSON', () {
      final sr = SearchResult.fromJson({
        'content': 'a figure caption',
        'score': 0.9,
        'document_id': 'doc-1',
        'doc_item_refs': ['#/texts/24', '#/pictures/0'],
        'image_data': {'#/pictures/0': 'aGVsbG8='},
      });
      expect(sr.imageData, {'#/pictures/0': 'aGVsbG8='});
    });

    test('absent image_data is null', () {
      final sr = SearchResult.fromJson({'content': 'x', 'score': 0.1});
      expect(sr.imageData, isNull);
    });

    test('round-trips image_data through toJson', () {
      final sr = SearchResult.fromJson({
        'content': 'x',
        'score': 0.1,
        'image_data': {'#/pictures/1': 'd29ybGQ='},
      });
      expect(sr.toJson()['image_data'], {'#/pictures/1': 'd29ybGQ='});
    });
  });
}
