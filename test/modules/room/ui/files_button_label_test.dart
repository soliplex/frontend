import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/ui/room_screen.dart';

void main() {
  group('filesButtonLabel', () {
    test('shows both counts when room and thread uploads exist', () {
      expect(
        filesButtonLabel(
            roomCount: 2, threadCount: 3, assistantCount: 0, newCount: 0),
        '2 room · 3 thread',
      );
    });

    test('shows room only when no thread uploads', () {
      expect(
        filesButtonLabel(
            roomCount: 1, threadCount: 0, assistantCount: 0, newCount: 0),
        '1 room',
      );
    });

    test('shows thread only when no room uploads', () {
      expect(
        filesButtonLabel(
            roomCount: 0, threadCount: 5, assistantCount: 0, newCount: 0),
        '5 thread',
      );
    });

    test('handles single counts', () {
      expect(
        filesButtonLabel(
            roomCount: 1, threadCount: 1, assistantCount: 0, newCount: 0),
        '1 room · 1 thread',
      );
    });

    test('adds the assistant count', () {
      expect(
        filesButtonLabel(
            roomCount: 1, threadCount: 0, assistantCount: 3, newCount: 0),
        '1 room · 3 from the assistant',
      );
    });

    test('says how many assistant files are new', () {
      expect(
        filesButtonLabel(
            roomCount: 0, threadCount: 0, assistantCount: 3, newCount: 2),
        '3 from the assistant (2 new)',
      );
    });

    test('is "Files" when nothing is counted', () {
      // Every list empty but the assistant list failed: the button still
      // shows, with its error icon.
      expect(
        filesButtonLabel(
            roomCount: 0, threadCount: 0, assistantCount: 0, newCount: 0),
        'Files',
      );
    });
  });
}
