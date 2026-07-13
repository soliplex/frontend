import 'package:soliplex_client/src/schema/agui_features/rag.dart';
import 'package:test/test.dart';

void main() {
  group('SearchResult.parsePictureCaptions', () {
    test('drops non-string entries', () {
      expect(
        SearchResult.parsePictureCaptions({'#/pictures/0': 'ok', '#/p': 5}),
        {'#/pictures/0': 'ok'},
      );
    });

    test('returns an empty map when absent or non-map', () {
      expect(SearchResult.parsePictureCaptions(null), isEmpty);
      expect(SearchResult.parsePictureCaptions('nope'), isEmpty);
    });
  });
}
