import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/status_message/status_message_window_format.dart';

void main() {
  group('formatWindowBound', () {
    // Local DateTimes (not UTC) so toLocal() is identity and the test is
    // timezone-independent. 2026-06-28 is a Sunday, 2026-06-29 a Monday.
    test('full date and 12-hour time', () {
      expect(formatWindowBound(DateTime(2026, 6, 28, 13, 16)),
          'Sun, Jun 28 · 1:16 PM');
    });
    test('same local day omits the date', () {
      expect(
        formatWindowBound(DateTime(2026, 6, 28, 15, 16),
            sameDayAs: DateTime(2026, 6, 28, 13, 16)),
        '3:16 PM',
      );
    });
    test('different local day keeps the date', () {
      expect(
        formatWindowBound(DateTime(2026, 6, 29, 3, 16),
            sameDayAs: DateTime(2026, 6, 28, 13, 16)),
        'Mon, Jun 29 · 3:16 AM',
      );
    });
    test('midnight and noon read as 12', () {
      expect(formatWindowBound(DateTime(2026, 6, 28, 0, 5)),
          'Sun, Jun 28 · 12:05 AM');
      expect(formatWindowBound(DateTime(2026, 6, 28, 12, 0)),
          'Sun, Jun 28 · 12:00 PM');
    });
  });
}
