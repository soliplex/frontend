import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/lobby/room_activity_format.dart';

void main() {
  final now = DateTime(2026, 6, 9, 12);

  group('formatRelativeActivity', () {
    test('renders minute/hour/day granularity then a numeric date', () {
      expect(
        formatRelativeActivity(now.subtract(const Duration(seconds: 30)),
            now: now),
        'Just now',
      );
      expect(
        formatRelativeActivity(now.subtract(const Duration(minutes: 5)),
            now: now),
        '5m ago',
      );
      expect(
        formatRelativeActivity(now.subtract(const Duration(hours: 3)),
            now: now),
        '3h ago',
      );
      expect(
        formatRelativeActivity(now.subtract(const Duration(days: 2)), now: now),
        '2d ago',
      );
      // Older than a week → numeric date (M/D/YYYY).
      expect(
        formatRelativeActivity(DateTime(2026, 1, 15), now: now),
        '1/15/2026',
      );
    });
  });

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
  });
}
