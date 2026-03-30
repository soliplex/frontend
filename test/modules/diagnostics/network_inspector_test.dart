import 'package:flutter_test/flutter_test.dart';
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

    test('starts with empty events list', () {
      expect(inspector.events, isEmpty);
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

    test('accumulates multiple events in order', () {
      final req = createRequestEvent();
      final resp = createResponseEvent();
      inspector.onRequest(req);
      inspector.onResponse(resp);
      expect(inspector.events, hasLength(2));
      expect(inspector.events[0], req);
      expect(inspector.events[1], resp);
    });

    test('events getter returns unmodifiable list', () {
      inspector.onRequest(createRequestEvent());
      expect(
        () => inspector.events.add(createResponseEvent()),
        throwsUnsupportedError,
      );
    });

    test('clear() empties the events list', () {
      inspector.onRequest(createRequestEvent());
      inspector.onResponse(createResponseEvent());
      inspector.clear();
      expect(inspector.events, isEmpty);
    });

    test('notifyListeners fires when event is added', () {
      var notifyCount = 0;
      inspector.addListener(() => notifyCount++);

      inspector.onRequest(createRequestEvent());
      expect(notifyCount, 1);

      inspector.onResponse(createResponseEvent());
      expect(notifyCount, 2);
    });

    test('notifyListeners fires on clear()', () {
      inspector.onRequest(createRequestEvent());

      var notifyCount = 0;
      inspector.addListener(() => notifyCount++);

      inspector.clear();
      expect(notifyCount, 1);
    });
  });
}
