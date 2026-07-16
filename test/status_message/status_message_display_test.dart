import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/status_message/status_message.dart';
import 'package:soliplex_frontend/src/status_message/status_message_display.dart';

StatusMessage _windowed(DateTime start, DateTime end) => StatusMessage(
      id: 'm',
      title: 't',
      body: 'b',
      intent: MessageIntent.warning,
      category: MessageCategory.maintenance,
      window: MessageWindow(start: start, end: end),
    );

void main() {
  final start = DateTime.utc(2026, 6, 28, 20);
  final end = DateTime.utc(2026, 6, 28, 22);

  group('resolveVisibility', () {
    test('windowless is persistent', () {
      final msg = StatusMessage(
          id: 'n',
          title: 't',
          body: 'b',
          intent: MessageIntent.info,
          category: MessageCategory.general);
      expect(resolveVisibility(msg, now: start), isA<MessagePersistent>());
    });
    test('before start is upcoming with remaining', () {
      final d = resolveVisibility(_windowed(start, end),
          now: start.subtract(const Duration(hours: 3)));
      expect(d, isA<MessageUpcoming>());
      expect((d as MessageUpcoming).remaining, const Duration(hours: 3));
    });
    test('exactly at start is active', () {
      expect(resolveVisibility(_windowed(start, end), now: start),
          isA<MessageActive>());
    });
    test('mid-window is active', () {
      expect(
          resolveVisibility(_windowed(start, end),
              now: start.add(const Duration(minutes: 30))),
          isA<MessageActive>());
    });
    test('at end is hidden', () {
      expect(resolveVisibility(_windowed(start, end), now: end),
          isA<MessageHidden>());
    });
    test('after end is hidden', () {
      expect(
          resolveVisibility(_windowed(start, end),
              now: end.add(const Duration(hours: 1))),
          isA<MessageHidden>());
    });
  });

  group('formatCountdown', () {
    test('days and hours', () {
      expect(formatCountdown(const Duration(days: 2, hours: 4, minutes: 30)),
          '2D 4H');
    });
    test('hours and minutes', () {
      expect(formatCountdown(const Duration(hours: 1, minutes: 20)), '1H 20M');
    });
    test('minutes only', () {
      expect(formatCountdown(const Duration(minutes: 5)), '5M');
    });
    test('negative clamps to zero', () {
      expect(formatCountdown(const Duration(seconds: -30)), '0M');
    });
  });
}
