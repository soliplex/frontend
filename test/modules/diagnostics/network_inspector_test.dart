import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/network_inspector.dart';

import '../../helpers/http_event_factories.dart';

void main() {
  group('NetworkInspector', () {
    late NetworkInspector inspector;

    setUp(() {
      inspector = NetworkInspector();
    });

    tearDown(() {
      inspector.dispose();
    });

    test('starts with empty event lists', () {
      expect(inspector.events, isEmpty);
      expect(inspector.concurrencyEvents, isEmpty);
    });

    test('collects request events via onRequest', () {
      inspector.onRequest(createRequestEvent());
      expect(inspector.events, hasLength(1));
    });

    test('collects response events via onResponse', () {
      inspector.onResponse(createResponseEvent());
      expect(inspector.events, hasLength(1));
    });

    test('collects error events via onError', () {
      inspector.onError(createErrorEvent());
      expect(inspector.events, hasLength(1));
    });

    test('collects stream start events via onStreamStart', () {
      inspector.onStreamStart(createStreamStartEvent());
      expect(inspector.events, hasLength(1));
    });

    test('collects stream end events via onStreamEnd', () {
      inspector.onStreamEnd(createStreamEndEvent());
      expect(inspector.events, hasLength(1));
    });

    test('collects concurrency wait events via onConcurrencyWait', () {
      inspector.onConcurrencyWait(createConcurrencyWaitEvent());
      expect(inspector.concurrencyEvents, hasLength(1));
    });

    test('concurrency events do not pollute the http events list', () {
      inspector.onConcurrencyWait(createConcurrencyWaitEvent());
      expect(inspector.events, isEmpty);
    });

    test('accumulates multiple events in order', () {
      final req = createRequestEvent();
      final resp = createResponseEvent();
      inspector.onRequest(req);
      inspector.onResponse(resp);
      expect(inspector.events, hasLength(2));
      expect(inspector.events[0], req);
      expect(inspector.events[1], resp);
    });

    test('clear() empties the events list', () {
      inspector.onRequest(createRequestEvent());
      inspector.onResponse(createResponseEvent());
      inspector.clear();
      expect(inspector.events, isEmpty);
    });

    test('clear() empties both events and concurrencyEvents', () {
      inspector.onRequest(createRequestEvent());
      inspector.onConcurrencyWait(createConcurrencyWaitEvent());
      inspector.clear();
      expect(inspector.events, isEmpty);
      expect(inspector.concurrencyEvents, isEmpty);
    });

    test('notifyListeners fires when event is added', () {
      var notifyCount = 0;
      inspector.addListener(() => notifyCount++);

      inspector.onRequest(createRequestEvent());
      expect(notifyCount, 1);

      inspector.onResponse(createResponseEvent());
      expect(notifyCount, 2);
    });

    test('notifyListeners fires when concurrency event is added', () {
      var notifyCount = 0;
      inspector.addListener(() => notifyCount++);

      inspector.onConcurrencyWait(createConcurrencyWaitEvent());
      expect(notifyCount, 1);
    });

    test('is safe to receive events after dispose', () {
      inspector
        ..onRequest(createRequestEvent())
        ..dispose();

      // Post-dispose events are silently dropped instead of throwing
      // a "Cannot use disposed ChangeNotifier" error. The HTTP stack
      // often outlives the UI — logout, route teardown, etc.
      expect(
        () => inspector.onConcurrencyWait(createConcurrencyWaitEvent()),
        returnsNormally,
      );
      expect(() => inspector.onRequest(createRequestEvent()), returnsNormally);
    });

    test('notifyListeners fires on clear()', () {
      inspector.onRequest(createRequestEvent());

      var notifyCount = 0;
      inspector.addListener(() => notifyCount++);

      inspector.clear();
      expect(notifyCount, 1);
    });
  });

  group('NetworkInspector bounded queues', () {
    test('events queue caps at maxEvents and drops the oldest first', () {
      final inspector = NetworkInspector(maxEvents: 3);
      addTearDown(inspector.dispose);

      final events = List.generate(
        5,
        (i) => createRequestEvent(requestId: 'r$i'),
      );
      for (final e in events) {
        inspector.onRequest(e);
      }

      expect(inspector.events, hasLength(3));
      expect(
        inspector.events.map((e) => (e as HttpRequestEvent).requestId),
        ['r2', 'r3', 'r4'],
        reason: 'oldest entries must drop first (FIFO)',
      );
    });

    test('concurrencyEvents queue caps independently of events queue', () {
      final inspector = NetworkInspector(maxEvents: 2);
      addTearDown(inspector.dispose);

      for (var i = 0; i < 4; i++) {
        inspector.onConcurrencyWait(createConcurrencyWaitEvent());
      }
      for (var i = 0; i < 4; i++) {
        inspector.onRequest(createRequestEvent());
      }

      expect(inspector.concurrencyEvents, hasLength(2));
      expect(inspector.events, hasLength(2));
    });

    test('rejects non-positive maxEvents', () {
      expect(
        () => NetworkInspector(maxEvents: 0),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => NetworkInspector(maxEvents: -1),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
