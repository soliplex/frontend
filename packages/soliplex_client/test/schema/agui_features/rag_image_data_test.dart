import 'package:soliplex_client/src/schema/agui_features/rag.dart';
import 'package:test/test.dart';

void main() {
  group('SearchResult.parseImageData', () {
    test('drops non-string keys and values', () {
      final parsed = SearchResult.parseImageData({
        '#/pictures/0': 'aGVsbG8=',
        '#/pictures/1': 42,
        7: 'Zm9v',
      });
      expect(parsed, {'#/pictures/0': 'aGVsbG8='});
    });

    test('returns an empty map for a non-map value', () {
      expect(SearchResult.parseImageData('not-a-map'), isEmpty);
      expect(SearchResult.parseImageData(null), isEmpty);
    });
  });
}
