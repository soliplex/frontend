import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/lobby/room_activity_format.dart';

void main() {
  final now = DateTime(2026, 6, 9, 12);

  group('bucketFor', () {
    test('null maps to the no-activity bucket', () {
      expect(bucketFor(null, now: now), ActivityBucket.none);
    });

    test('groups by calendar-relative recency', () {
      expect(bucketFor(now.subtract(const Duration(hours: 2)), now: now),
          ActivityBucket.today);
      // Yesterday is the previous calendar day, even if <24h ago.
      expect(bucketFor(DateTime(2026, 6, 8, 23), now: now),
          ActivityBucket.yesterday);
      expect(
          bucketFor(DateTime(2026, 6, 5), now: now), ActivityBucket.thisWeek);
      expect(
          bucketFor(DateTime(2026, 5, 25), now: now), ActivityBucket.thisMonth);
      expect(bucketFor(DateTime(2026, 1, 1), now: now), ActivityBucket.older);
    });

    test('places the week and month cusps on the older side', () {
      // 6 vs 7 calendar days: still this week, then this month.
      expect(
          bucketFor(DateTime(2026, 6, 3), now: now), ActivityBucket.thisWeek);
      expect(
          bucketFor(DateTime(2026, 6, 2), now: now), ActivityBucket.thisMonth);
      // 29 vs 30 calendar days: this month, then older.
      expect(
          bucketFor(DateTime(2026, 5, 11), now: now), ActivityBucket.thisMonth);
      expect(bucketFor(DateTime(2026, 5, 10), now: now), ActivityBucket.older);
    });
  });
}
