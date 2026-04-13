import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/ui/room_screen.dart';

void main() {
  group('uploadChipLabel', () {
    test('shows both counts when room and thread uploads exist', () {
      expect(uploadChipLabel(2, 3), '2 room \u00b7 3 thread');
    });

    test('shows room only when no thread uploads', () {
      expect(uploadChipLabel(1, 0), '1 room');
    });

    test('shows thread only when no room uploads', () {
      expect(uploadChipLabel(0, 5), '5 thread');
    });

    test('handles single counts', () {
      expect(uploadChipLabel(1, 1), '1 room \u00b7 1 thread');
    });
  });
}
