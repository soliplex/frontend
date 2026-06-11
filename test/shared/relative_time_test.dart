import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/shared/relative_time.dart';

void main() {
  final now = DateTime(2026, 6, 9, 12);

  group('formatRelativeTime', () {
    test('renders minute/hour/day granularity then a numeric date', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(seconds: 30)), now: now),
        'Just now',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(minutes: 5)), now: now),
        '5m ago',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(hours: 3)), now: now),
        '3h ago',
      );
      expect(
        formatRelativeTime(now.subtract(const Duration(days: 2)), now: now),
        '2d ago',
      );
      expect(
        formatRelativeTime(DateTime(2026, 1, 15), now: now),
        '1/15/2026',
      );
    });

    test('switches label exactly at each threshold', () {
      String at(Duration ago) =>
          formatRelativeTime(now.subtract(ago), now: now);
      expect(at(const Duration(seconds: 59)), 'Just now');
      expect(at(const Duration(minutes: 1)), '1m ago');
      expect(at(const Duration(minutes: 59)), '59m ago');
      expect(at(const Duration(hours: 1)), '1h ago');
      expect(at(const Duration(hours: 23)), '23h ago');
      expect(at(const Duration(hours: 24)), '1d ago');
      expect(at(const Duration(days: 6)), '6d ago');
      expect(at(const Duration(days: 7)), '6/2/2026');
    });

    // Regression for issue #338: the numeric-date fallback must read the
    // viewer's local calendar fields, not the raw UTC instant. Backend
    // timestamps arrive in UTC, so a date rendered from UTC fields is off by a
    // day for viewers whose local day differs. Caveat: this can only fail on a
    // runner whose zone differs from UTC; on a UTC runner both sides coincide.
    test('renders the numeric-date fallback in the viewer local zone', () {
      final utcInstant = DateTime.utc(2026, 1, 15, 3);
      final local = utcInstant.toLocal();
      final reference = utcInstant.add(const Duration(days: 30));
      expect(
        formatRelativeTime(utcInstant, now: reference),
        '${local.month}/${local.day}/${local.year}',
      );
    });
  });
}
