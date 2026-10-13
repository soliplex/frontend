import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/ui/room_screen.dart';

void main() {
  group('filesButtonLabel', () {
    test('shows both counts when room and thread uploads exist', () {
      expect(
        filesButtonLabel(roomCount: 2, threadCount: 3, workspaceCount: 0),
        '2 room · 3 thread',
      );
    });

    test('shows room only when no thread uploads', () {
      expect(
        filesButtonLabel(roomCount: 1, threadCount: 0, workspaceCount: 0),
        '1 room',
      );
    });

    test('shows thread only when no room uploads', () {
      expect(
        filesButtonLabel(roomCount: 0, threadCount: 5, workspaceCount: 0),
        '5 thread',
      );
    });

    test('adds the workspace count', () {
      expect(
        filesButtonLabel(roomCount: 1, threadCount: 1, workspaceCount: 3),
        '1 room · 1 thread · 3 in workspace',
      );
    });

    test('is "Files" when nothing is counted', () {
      // The label when the only content is a failed workspace list.
      expect(
        filesButtonLabel(roomCount: 0, threadCount: 0, workspaceCount: 0),
        'Files',
      );
    });
  });
}
