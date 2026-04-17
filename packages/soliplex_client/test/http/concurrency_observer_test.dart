import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

class _RecordingObserver implements ConcurrencyObserver {
  final events = <ConcurrencyWaitEvent>[];

  @override
  void onConcurrencyWait(ConcurrencyWaitEvent event) => events.add(event);
}

void main() {
  group('ConcurrencyWaitEvent', () {
    test('events with identical fields are equal', () {
      final now = DateTime.now();
      final a = ConcurrencyWaitEvent(
        acquisitionId: 'req-1',
        timestamp: now,
        uri: Uri.parse('https://api.example.com/x'),
        waitDuration: const Duration(milliseconds: 100),
        queueDepthAtEnqueue: 2,
        slotsInUseAfterAcquire: 5,
      );
      final b = ConcurrencyWaitEvent(
        acquisitionId: 'req-1',
        timestamp: now,
        uri: Uri.parse('https://api.example.com/x'),
        waitDuration: const Duration(milliseconds: 100),
        queueDepthAtEnqueue: 2,
        slotsInUseAfterAcquire: 5,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('ConcurrencyWaitEvent invariants', () {
    test('rejects empty acquisitionId', () {
      expect(
        () => ConcurrencyWaitEvent(
          acquisitionId: '',
          timestamp: DateTime.now(),
          uri: Uri.parse('https://x/y'),
          waitDuration: Duration.zero,
          queueDepthAtEnqueue: 0,
          slotsInUseAfterAcquire: 1,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects negative queueDepthAtEnqueue', () {
      expect(
        () => ConcurrencyWaitEvent(
          acquisitionId: 'req-1',
          timestamp: DateTime.now(),
          uri: Uri.parse('https://x/y'),
          waitDuration: Duration.zero,
          queueDepthAtEnqueue: -1,
          slotsInUseAfterAcquire: 1,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects slotsInUseAfterAcquire below 1', () {
      expect(
        () => ConcurrencyWaitEvent(
          acquisitionId: 'req-1',
          timestamp: DateTime.now(),
          uri: Uri.parse('https://x/y'),
          waitDuration: Duration.zero,
          queueDepthAtEnqueue: 0,
          slotsInUseAfterAcquire: 0,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('ConcurrencyObserver', () {
    test('observers receive events via onConcurrencyWait', () {
      final observer = _RecordingObserver();
      final event = ConcurrencyWaitEvent(
        acquisitionId: 'req-1',
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
