import 'package:soliplex_client/src/schema/agui_features/rag.dart';
import 'package:test/test.dart';

void main() {
  group('SearchResult picture_captions', () {
    test('populates pictureCaptions from picture_captions', () {
      final r = SearchResult.fromJson({
        'content': 'x',
        'score': 0.5,
        'picture_captions': {'#/pictures/0': 'Figure 1: revenue'},
      });
      expect(r.pictureCaptions, {'#/pictures/0': 'Figure 1: revenue'});
    });

    test('defaults to empty when absent', () {
      final r = SearchResult.fromJson({'content': 'x', 'score': 0.5});
      expect(r.pictureCaptions, isEmpty);
    });

    test('drops non-string entries', () {
      expect(
        SearchResult.parsePictureCaptions({'#/pictures/0': 'ok', '#/p': 5}),
        {'#/pictures/0': 'ok'},
      );
    });
  });
}
