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

    test('malformed window throws FormatException', () {
      expect(
        () => StatusMessage.fromJson({
          'id': 'x',
          'title': 't',
          'body': 'b',
          'window': {'start': 'not-a-date'}
        }),
        throwsFormatException,
      );
    });
  });
}
