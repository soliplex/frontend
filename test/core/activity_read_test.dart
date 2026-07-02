import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/core/activity_read.dart';

void main() {
  group('latestSeen', () {
    final early = DateTime.utc(2026, 1, 1);
    final later = DateTime.utc(2026, 6, 1);

    test('returns the later of two markers', () {
      expect(latestSeen(early, later), later);
      expect(latestSeen(later, early), later);
    });

    test('null never wins (treated as never-seen)', () {
      expect(latestSeen(null, later), later);
      expect(latestSeen(later, null), later);
      expect(latestSeen(null, null), isNull);
    });
  });
}
