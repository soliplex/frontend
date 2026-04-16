import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

class _RecordingObserver implements ConcurrencyObserver {
  final events = <HttpConcurrencyWaitEvent>[];

  @override
  void onConcurrencyWait(HttpConcurrencyWaitEvent event) => events.add(event);
}

void main() {
  group('HttpConcurrencyWaitEvent', () {
    test('stores all required fields', () {
      final now = DateTime.now();
      final event = HttpConcurrencyWaitEvent(
        requestId: 'req-1',
        timestamp: now,
        uri: Uri.parse('https://api.example.com/x'),
        waitDuration: const Duration(milliseconds: 250),
        queueDepthAtEnqueue: 3,
        slotsInUseAfterAcquire: 6,
      );

      expect(event.requestId, equals('req-1'));
      expect(event.timestamp, equals(now));
      expect(event.uri.toString(), equals('https://api.example.com/x'));
      expect(event.waitDuration, equals(const Duration(milliseconds: 250)));
      expect(event.queueDepthAtEnqueue, equals(3));
      expect(event.slotsInUseAfterAcquire, equals(6));
    });

    test('events with same requestId compare equal', () {
      final a = HttpConcurrencyWaitEvent(
        requestId: 'req-1',
        timestamp: DateTime.now(),
        uri: Uri.parse('https://api.example.com/x'),
        waitDuration: Duration.zero,
        queueDepthAtEnqueue: 0,
        slotsInUseAfterAcquire: 1,
      );
      final b = HttpConcurrencyWaitEvent(
        requestId: 'req-1',
        timestamp: DateTime.now().add(const Duration(seconds: 1)),
        uri: Uri.parse('https://api.example.com/y'),
        waitDuration: const Duration(milliseconds: 500),
        queueDepthAtEnqueue: 5,
        slotsInUseAfterAcquire: 6,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('toString includes key fields', () {
      final event = HttpConcurrencyWaitEvent(
        requestId: 'req-1',
        timestamp: DateTime.now(),
        uri: Uri.parse('https://api.example.com/x'),
        waitDuration: const Duration(milliseconds: 250),
        queueDepthAtEnqueue: 3,
        slotsInUseAfterAcquire: 6,
      );
      expect(event.toString(), contains('req-1'));
      expect(event.toString(), contains('250'));
    });
  });

  group('ConcurrencyObserver', () {
    test('observers receive events via onConcurrencyWait', () {
      final observer = _RecordingObserver();
      final event = HttpConcurrencyWaitEvent(
        requestId: 'req-1',
        timestamp: DateTime.now(),
        uri: Uri.parse('https://api.example.com/x'),
        waitDuration: const Duration(milliseconds: 100),
        queueDepthAtEnqueue: 2,
        slotsInUseAfterAcquire: 5,
      );

      observer.onConcurrencyWait(event);

      expect(observer.events, equals([event]));
    });
  });
}
