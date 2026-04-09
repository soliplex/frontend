import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

void main() {
  group('FeedbackType', () {
    test('thumbsUp serializes to thumbs_up', () {
      expect(FeedbackType.thumbsUp.toJson(), 'thumbs_up');
    });

    test('thumbsDown serializes to thumbs_down', () {
      expect(FeedbackType.thumbsDown.toJson(), 'thumbs_down');
    });
  });
}
