import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/shared/local_time_format.dart';

void main() {
  // Local DateTimes so the calendar fields are read as-is (timezone-independent).
  group('formatClock12', () {
    test('afternoon', () {
      expect(formatClock12(DateTime(2026, 6, 28, 13, 16)), '1:16 PM');
    });
    test('midnight and noon read as 12', () {
      expect(formatClock12(DateTime(2026, 6, 28, 0, 5)), '12:05 AM');
      expect(formatClock12(DateTime(2026, 6, 28, 12, 0)), '12:00 PM');
    });
    test('minute is zero-padded, hour is not', () {
      expect(formatClock12(DateTime(2026, 6, 28, 9, 3)), '9:03 AM');
    });
  });

  group('weekdayAbbrev / monthAbbrev', () {
    test('three-letter labels', () {
      expect(weekdayAbbrev(DateTime(2026, 6, 28)), 'Sun'); // Sunday
      expect(weekdayAbbrev(DateTime(2026, 6, 29)), 'Mon'); // Monday
      expect(monthAbbrev(DateTime(2026, 6, 28)), 'Jun');
      expect(monthAbbrev(DateTime(2026, 1, 1)), 'Jan');
    });
  });

  group('isSameCalendarDay', () {
    test('same local day, different hours', () {
      expect(
        isSameCalendarDay(DateTime(2026, 3, 15, 1), DateTime(2026, 3, 15, 23)),
        isTrue,
      );
    });
    test('adjacent days are different', () {
      expect(
        isSameCalendarDay(DateTime(2026, 3, 15, 23), DateTime(2026, 3, 16, 1)),
        isFalse,
      );
    });
  });
}
