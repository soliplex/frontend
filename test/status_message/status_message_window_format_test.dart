import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/status_message/status_message_window_format.dart';

void main() {
  group('formatWindowRange', () {
    // Local DateTimes (not UTC) so toLocal() is identity and the test is
    // timezone-independent. 2026-07-17 is a Friday, 2026-07-18 a Saturday.
    test('same day collapses to one date with an en-dash time range', () {
      expect(
        formatWindowRange(
            DateTime(2026, 7, 17, 16, 44), DateTime(2026, 7, 17, 18, 44)),
        'Fri, Jul 17 · 4:44 PM – 6:44 PM',
      );
    });
    test('spanning days spells out both ends joined by "to"', () {
      expect(
        formatWindowRange(
            DateTime(2026, 7, 17, 16, 44), DateTime(2026, 7, 18, 3, 16)),
        'Fri, Jul 17 · 4:44 PM to Sat, Jul 18 · 3:16 AM',
      );
    });
    test('stacked spanning breaks after "to" so the end date starts a new line',
        () {
      expect(
        formatWindowRange(
            DateTime(2026, 7, 17, 16, 44), DateTime(2026, 7, 18, 3, 16),
            stacked: true),
        'Fri, Jul 17 · 4:44 PM to\nSat, Jul 18 · 3:16 AM',
      );
    });
    test('stacked has no effect on a same-day range', () {
      expect(
        formatWindowRange(
            DateTime(2026, 7, 17, 16, 44), DateTime(2026, 7, 17, 18, 44),
            stacked: true),
        'Fri, Jul 17 · 4:44 PM – 6:44 PM',
      );
    });
    test('midnight and noon read as 12', () {
      expect(
        formatWindowRange(
            DateTime(2026, 7, 17, 0, 5), DateTime(2026, 7, 17, 12, 0)),
        'Fri, Jul 17 · 12:05 AM – 12:00 PM',
      );
    });
  });
}
