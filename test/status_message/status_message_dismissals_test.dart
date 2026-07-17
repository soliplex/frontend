import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/status_message/status_message_dismissals.dart';

void main() {
  group('StatusMessageDismissals', () {
    test('marks and reports a dismissed message', () {
      final d = StatusMessageDismissals();
      expect(d.isDismissed('https://a', 'm1'), isFalse);
      d.markDismissed('https://a', 'm1');
      expect(d.isDismissed('https://a', 'm1'), isTrue);
    });

    test('scopes by server and by message id', () {
      final d = StatusMessageDismissals()..markDismissed('https://a', 'm1');
      expect(d.isDismissed('https://b', 'm1'), isFalse); // other server
      expect(d.isDismissed('https://a', 'm2'), isFalse); // other message
    });

    test('clear(serverKey) removes only that server', () {
      final d = StatusMessageDismissals()
        ..markDismissed('https://a', 'm1')
        ..markDismissed('https://b', 'm1');
      d.clear(serverKey: 'https://a');
      expect(d.isDismissed('https://a', 'm1'), isFalse);
      expect(d.isDismissed('https://b', 'm1'), isTrue);
    });

    test('clear() removes everything', () {
      final d = StatusMessageDismissals()
        ..markDismissed('https://a', 'm1')
        ..markDismissed('https://b', 'm1');
      d.clear();
      expect(d.isDismissed('https://a', 'm1'), isFalse);
      expect(d.isDismissed('https://b', 'm1'), isFalse);
    });
  });
}
