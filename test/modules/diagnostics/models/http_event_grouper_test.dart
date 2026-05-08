import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/models/http_event_group.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/models/http_event_grouper.dart';

import '../../../helpers/http_event_factories.dart';

void main() {
  group('groupHttpEvents', () {
    test('returns empty list for empty input', () {
      expect(groupHttpEvents([]), isEmpty);
    });

    test('groups request and response by requestId', () {
      final events = [
        createRequestEvent(requestId: 'req-1'),
        createResponseEvent(requestId: 'req-1', statusCode: 200),
      ];
      final groups = groupHttpEvents(events);
      expect(groups, hasLength(1));
      expect(groups[0].requestId, 'req-1');
      expect(groups[0].request, isNotNull);
      expect(groups[0].response, isNotNull);
      expect(groups[0].status, HttpEventStatus.success);
    });

    test('creates separate groups for different requestIds', () {
      final events = [
        createRequestEvent(requestId: 'req-1'),
        createRequestEvent(requestId: 'req-2'),
        createResponseEvent(requestId: 'req-1'),
      ];
      final groups = groupHttpEvents(events);
      expect(groups, hasLength(2));
    });

    test('sorts groups by timestamp oldest first', () {
      final events = [
        createRequestEvent(
          requestId: 'req-2',
          timestamp: DateTime.utc(2026, 1, 1, 13),
        ),
        createRequestEvent(
          requestId: 'req-1',
          timestamp: DateTime.utc(2026, 1, 1, 12),
        ),
      ];
      final groups = groupHttpEvents(events);
      expect(groups[0].requestId, 'req-1');
      expect(groups[1].requestId, 'req-2');
    });

    test('groups streaming events correctly', () {
      final events = [
        createStreamStartEvent(requestId: 'req-1'),
        createStreamEndEvent(requestId: 'req-1'),
      ];
      final groups = groupHttpEvents(events);
      expect(groups, hasLength(1));
      expect(groups[0].isStream, isTrue);
      expect(groups[0].status, HttpEventStatus.streamComplete);
    });

    test('handles response with no matching request', () {
      final events = [
        createResponseEvent(requestId: 'unmatched', statusCode: 200),
      ];
      final groups = groupHttpEvents(events);
      expect(groups, hasLength(1));
      expect(groups[0].request, isNull);
      expect(groups[0].response, isNotNull);
    });

    test('groups interleaved requests from multiple runs', () {
      final events = [
        createRequestEvent(
          requestId: 'req-a',
          timestamp: DateTime.utc(2026, 1, 1, 12, 0),
        ),
        createStreamStartEvent(
          requestId: 'req-b',
          timestamp: DateTime.utc(2026, 1, 1, 12, 1),
        ),
        createResponseEvent(requestId: 'req-a'),
        createStreamEndEvent(requestId: 'req-b'),
      ];
      final groups = groupHttpEvents(events);
      expect(groups, hasLength(2));
      expect(groups[0].requestId, 'req-a');
      expect(groups[0].status, HttpEventStatus.success);
      expect(groups[1].requestId, 'req-b');
      expect(groups[1].status, HttpEventStatus.streamComplete);
    });
  });
}
