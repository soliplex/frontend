import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/status_message/status_message.dart';

void main() {
  group('StatusMessage.fromJson', () {
    test('parses a windowed maintenance message', () {
      final msg = StatusMessage.fromJson({
        'id': 'm1',
        'title': 'Scheduled maintenance',
        'body': 'Down Sun 1-3 PM PT.',
        'intent': 'warning',
        'category': 'maintenance',
        'window': {
          'start': '2026-06-28T20:16:00Z',
          'end': '2026-06-28T22:16:00Z'
        },
      });
      expect(msg.id, 'm1');
      expect(msg.intent, MessageIntent.warning);
      expect(msg.category, MessageCategory.maintenance);
      expect(msg.window!.start, DateTime.utc(2026, 6, 28, 20, 16));
      expect(msg.window!.end, DateTime.utc(2026, 6, 28, 22, 16));
    });

    test('parses a windowless notice with defaults', () {
      final msg = StatusMessage.fromJson(
          {'id': 'n1', 'title': 'Heads up', 'body': 'Hi'});
      expect(msg.window, isNull);
      expect(msg.intent, MessageIntent.info);
      expect(msg.category, MessageCategory.general);
    });

    test('unknown intent/category fall back to info/general', () {
      final msg = StatusMessage.fromJson({
        'id': 'x',
        'title': 't',
        'body': 'b',
        'intent': 'nope',
        'category': 'nope'
      });
      expect(msg.intent, MessageIntent.info);
      expect(msg.category, MessageCategory.general);
    });

    test('missing title throws FormatException', () {
      expect(() => StatusMessage.fromJson({'id': 'x', 'body': 'b'}),
          throwsFormatException);
    });

    // A malformed window degrades to windowless — the message text still shows
    // rather than the whole announcement being dropped.
    StatusMessage windowed(Object? window) => StatusMessage.fromJson(
        {'id': 'x', 'title': 't', 'body': 'b', 'window': window});

    test('a non-object window drops to windowless, keeping the message', () {
      final msg = windowed('soon');
      expect(msg.window, isNull);
      expect(msg.title, 't');
    });

    test('an unparseable window bound drops to windowless', () {
      expect(
          windowed({'start': 'not-a-date', 'end': '2026-06-28T22:16:00Z'})
              .window,
          isNull);
    });

    test('a naive (non-UTC) window bound drops to windowless', () {
      expect(
          windowed({
            'start': '2026-06-28T20:16:00',
            'end': '2026-06-28T22:16:00Z'
          }).window,
          isNull);
    });
  });

  group('value equality', () {
    // Load-bearing: the controller republishes a Signal<StatusMessage?> on
    // each poll, and value equality is what suppresses rebuilds when the file
    // is unchanged.
    StatusMessage build({String id = 'm', MessageWindow? window}) =>
        StatusMessage(
          id: id,
          title: 't',
          body: 'b',
          intent: MessageIntent.warning,
          category: MessageCategory.maintenance,
          window: window,
        );

    test('equal when all fields (incl. window) match', () {
      final w1 = MessageWindow(
          start: DateTime.utc(2026, 6, 28, 20),
          end: DateTime.utc(2026, 6, 28, 22));
      final w2 = MessageWindow(
          start: DateTime.utc(2026, 6, 28, 20),
          end: DateTime.utc(2026, 6, 28, 22));
      expect(build(window: w1), build(window: w2));
      expect(build(window: w1).hashCode, build(window: w2).hashCode);
    });

    test('differ in one field are not equal', () {
      expect(build(id: 'a'), isNot(build(id: 'b')));
    });
  });
}
