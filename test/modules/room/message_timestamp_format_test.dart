import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/message_timestamp_format.dart';

void main() {
  // Sunday 2026-03-15, noon, local. March avoids any DST transition.
  final now = DateTime(2026, 3, 15, 12);

  group('formatMessageCaption', () {
    test('today shows time only', () {
      expect(
        formatMessageCaption(DateTime(2026, 3, 15, 14, 14), now: now),
        '2:14 PM',
      );
    });

    test('yesterday is day-qualified', () {
      expect(
        formatMessageCaption(DateTime(2026, 3, 14, 16, 12), now: now),
        'Yesterday · 4:12 PM',
      );
    });

    test('2–6 days ago uses the abbreviated weekday', () {
      // 2026-03-12 is a Thursday, 3 days before Sunday the 15th.
      expect(
        formatMessageCaption(DateTime(2026, 3, 12, 9, 3), now: now),
        'Thu · 9:03 AM',
      );
    });

    test('earlier this year uses abbreviated month + day', () {
      expect(
        formatMessageCaption(DateTime(2026, 1, 5, 9, 3), now: now),
        'Jan 5 · 9:03 AM',
      );
    });

    test('older (prior year) includes the year', () {
      expect(
        formatMessageCaption(DateTime(2025, 3, 3, 9, 3), now: now),
        'Mar 3, 2025 · 9:03 AM',
      );
    });
  });

  group('formatMessageCaption clock + boundary edges', () {
    test('midnight is 12 AM, noon is 12 PM, minutes zero-padded', () {
      expect(
        formatMessageCaption(DateTime(2026, 3, 15, 0, 5), now: now),
        '12:05 AM',
      );
      expect(
        formatMessageCaption(DateTime(2026, 3, 15, 12), now: now),
        '12:00 PM',
      );
      expect(
        formatMessageCaption(DateTime(2026, 3, 15, 23, 59), now: now),
        '11:59 PM',
      );
    });

    test('buckets by calendar day, not elapsed hours, across midnight', () {
      // 1h05m apart but a calendar day apart: a naive now.difference(t).inDays
      // reads 0 (today); the UTC-floored day math reads 1 (yesterday).
      expect(
        formatMessageCaption(
          DateTime(2026, 3, 14, 23, 30),
          now: DateTime(2026, 3, 15, 0, 35),
        ),
        'Yesterday · 11:30 PM',
      );
    });

    test('day 6 is the weekday bucket, day 7 falls through to the date', () {
      // 2026-03-09 (Mon) is 6 days before Sunday the 15th → weekday.
      // 2026-03-08 (Sun) is 7 days ago → same weekday as today, so it shows
      // the date instead of "Sun".
      expect(
        formatMessageCaption(DateTime(2026, 3, 9, 9, 3), now: now),
        'Mon · 9:03 AM',
      );
      expect(
        formatMessageCaption(DateTime(2026, 3, 8, 9, 3), now: now),
        'Mar 8 · 9:03 AM',
      );
    });
  });

  group('formatDayDivider', () {
    test('today / yesterday are relative words', () {
      expect(formatDayDivider(DateTime(2026, 3, 15, 9), now: now), 'Today');
      expect(formatDayDivider(DateTime(2026, 3, 14, 9), now: now), 'Yesterday');
    });

    test('2–6 days ago is full weekday + date', () {
      expect(
        formatDayDivider(DateTime(2026, 3, 12, 9), now: now),
        'Thursday, March 12',
      );
    });

    test('this year is full month + day; older includes the year', () {
      expect(formatDayDivider(DateTime(2026, 1, 5, 9), now: now), 'January 5');
      expect(
        formatDayDivider(DateTime(2025, 3, 3, 9), now: now),
        'March 3, 2025',
      );
    });
  });
}
