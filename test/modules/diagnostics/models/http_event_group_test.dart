import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/models/http_event_group.dart';

import '../../../helpers/http_event_factories.dart';

void main() {
  group('HttpEventGroup', () {
    group('status', () {
      test('returns pending when only request exists', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          request: createRequestEvent(),
        );
        expect(group.status, HttpEventStatus.pending);
      });

      test('returns success for 2xx response', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          request: createRequestEvent(),
          response: createResponseEvent(statusCode: 200),
        );
        expect(group.status, HttpEventStatus.success);
      });

      test('returns clientError for 4xx response', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          request: createRequestEvent(),
          response: createResponseEvent(statusCode: 404),
        );
        expect(group.status, HttpEventStatus.clientError);
      });

      test('returns serverError for 5xx response', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          request: createRequestEvent(),
          response: createResponseEvent(statusCode: 500),
        );
        expect(group.status, HttpEventStatus.serverError);
      });

      test('returns networkError when error event exists', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          request: createRequestEvent(),
          error: createErrorEvent(),
        );
        expect(group.status, HttpEventStatus.networkError);
      });

      test('returns streaming when streamStart exists but no streamEnd', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          streamStart: createStreamStartEvent(),
        );
        expect(group.status, HttpEventStatus.streaming);
      });

      test('returns streamComplete when stream ends without error', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          streamStart: createStreamStartEvent(),
          streamEnd: createStreamEndEvent(),
        );
        expect(group.status, HttpEventStatus.streamComplete);
      });

      test('returns streamError when stream ends with error', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          streamStart: createStreamStartEvent(),
          streamEnd: createStreamEndEvent(
            error: const NetworkException(message: 'Stream failed'),
          ),
        );
        expect(group.status, HttpEventStatus.streamError);
      });
    });

    group('method', () {
      test('extracts from request event', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          request: createRequestEvent(method: 'POST'),
        );
        expect(group.method, 'POST');
      });

      test('extracts from error event when no request', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          error: createErrorEvent(method: 'DELETE'),
        );
        expect(group.method, 'DELETE');
      });

      test('extracts from streamStart when no request or error', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          streamStart: createStreamStartEvent(method: 'POST'),
        );
        expect(group.method, 'POST');
      });

      test('throws StateError when no events have method', () {
        final group = HttpEventGroup(requestId: 'req-1');
        expect(() => group.method, throwsStateError);
      });
    });

    group('toCurl', () {
      test('generates curl for GET request', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          request: createRequestEvent(
            method: 'GET',
            uri: Uri.parse('http://localhost/api/v1/rooms'),
          ),
        );
        final curl = group.toCurl();
        expect(curl, contains("'http://localhost/api/v1/rooms'"));
        expect(curl, isNot(contains('-X')));
      });

      test('generates curl with method for non-GET', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          request: createRequestEvent(
            method: 'POST',
            uri: Uri.parse('http://localhost/api/v1/rooms'),
            body: '{"prompt":"hello"}',
          ),
        );
        final curl = group.toCurl();
        expect(curl, contains('-X POST'));
        expect(curl, contains('-d'));
      });

      test('returns null when no request data', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          response: createResponseEvent(),
        );
        expect(group.toCurl(), isNull);
      });
    });

    group('formatBody', () {
      test('pretty-prints JSON map', () {
        final result = HttpEventGroup.formatBody({'key': 'value'});
        expect(result, contains('"key": "value"'));
      });

      test('pretty-prints JSON string', () {
        final result = HttpEventGroup.formatBody('{"key":"value"}');
        expect(result, contains('"key": "value"'));
      });

      test('returns original string for non-JSON', () {
        expect(HttpEventGroup.formatBody('plain text'), 'plain text');
      });

      test('returns empty string for null', () {
        expect(HttpEventGroup.formatBody(null), '');
      });
    });

    group('uri', () {
      test('extracts from request event', () {
        final uri = Uri.parse('http://localhost/api/v1/rooms');
        final group = HttpEventGroup(
          requestId: 'req-1',
          request: createRequestEvent(uri: uri),
        );
        expect(group.uri, uri);
      });

      test('extracts from error event when no request', () {
        final uri = Uri.parse('http://localhost/api/v1/rooms');
        final group = HttpEventGroup(
          requestId: 'req-1',
          error: createErrorEvent(uri: uri),
        );
        expect(group.uri, uri);
      });

      test('extracts from streamStart when no request or error', () {
        final uri = Uri.parse('http://localhost/api/v1/stream');
        final group = HttpEventGroup(
          requestId: 'req-1',
          streamStart: createStreamStartEvent(uri: uri),
        );
        expect(group.uri, uri);
      });

      test('throws StateError when no events have uri', () {
        final group = HttpEventGroup(requestId: 'req-1');
        expect(() => group.uri, throwsStateError);
      });
    });

    group('pathWithQuery', () {
      test('returns path without query string', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          request: createRequestEvent(
            uri: Uri.parse('http://localhost/api/v1/rooms'),
          ),
        );
        expect(group.pathWithQuery, '/api/v1/rooms');
      });

      test('returns path with query string', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          request: createRequestEvent(
            uri: Uri.parse('http://localhost/api/v1/rooms?page=2&size=10'),
          ),
        );
        expect(group.pathWithQuery, '/api/v1/rooms?page=2&size=10');
      });

      test('returns / for empty path', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          request: createRequestEvent(uri: Uri.parse('http://localhost')),
        );
        expect(group.pathWithQuery, '/');
      });
    });

    group('isStream', () {
      test('returns true when streamStart is present', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          streamStart: createStreamStartEvent(),
        );
        expect(group.isStream, isTrue);
      });

      test('returns false when no streamStart', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          request: createRequestEvent(),
        );
        expect(group.isStream, isFalse);
      });
    });

    group('methodLabel', () {
      test('returns SSE for streams', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          streamStart: createStreamStartEvent(method: 'POST'),
        );
        expect(group.methodLabel, 'SSE');
      });

      test('returns method for regular requests', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          request: createRequestEvent(method: 'DELETE'),
        );
        expect(group.methodLabel, 'DELETE');
      });
    });

    group('hasEvents', () {
      test('returns true when request exists', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          request: createRequestEvent(),
        );
        expect(group.hasEvents, isTrue);
      });

      test('returns true when only response exists', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          response: createResponseEvent(),
        );
        expect(group.hasEvents, isTrue);
      });

      test('returns false when no events', () {
        final group = HttpEventGroup(requestId: 'req-1');
        expect(group.hasEvents, isFalse);
      });
    });

    group('hasSpinner', () {
      test('returns true for pending status', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          request: createRequestEvent(),
        );
        expect(group.hasSpinner, isTrue);
      });

      test('returns true for streaming status', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          streamStart: createStreamStartEvent(),
        );
        expect(group.hasSpinner, isTrue);
      });

      test('returns false for completed request', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          request: createRequestEvent(),
          response: createResponseEvent(statusCode: 200),
        );
        expect(group.hasSpinner, isFalse);
      });

      test('returns false for completed stream', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          streamStart: createStreamStartEvent(),
          streamEnd: createStreamEndEvent(),
        );
        expect(group.hasSpinner, isFalse);
      });
    });

    group('timestamp', () {
      test('extracts from request event', () {
        final ts = DateTime.utc(2026, 3, 1, 10);
        final group = HttpEventGroup(
          requestId: 'req-1',
          request: createRequestEvent(timestamp: ts),
        );
        expect(group.timestamp, ts);
      });

      test('extracts from streamStart when no request', () {
        final ts = DateTime.utc(2026, 3, 1, 11);
        final group = HttpEventGroup(
          requestId: 'req-1',
          streamStart: createStreamStartEvent(timestamp: ts),
        );
        expect(group.timestamp, ts);
      });

      test('extracts from error event when no request or streamStart', () {
        final ts = DateTime.utc(2026, 3, 1, 12);
        final group = HttpEventGroup(
          requestId: 'req-1',
          error: createErrorEvent(timestamp: ts),
        );
        expect(group.timestamp, ts);
      });

      test('throws StateError when no events with timestamp', () {
        final group = HttpEventGroup(requestId: 'req-1');
        expect(() => group.timestamp, throwsStateError);
      });
    });

    group('statusDescription', () {
      test('returns "pending" for pending request', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          request: createRequestEvent(),
        );
        expect(group.statusDescription, 'pending');
      });

      test('includes status code for success', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          request: createRequestEvent(),
          response: createResponseEvent(statusCode: 200),
        );
        expect(group.statusDescription, 'success, status 200');
      });

      test('includes status code for client error', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          request: createRequestEvent(),
          response: createResponseEvent(statusCode: 404),
        );
        expect(group.statusDescription, 'client error, status 404');
      });

      test('returns "streaming" for active stream', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          streamStart: createStreamStartEvent(),
        );
        expect(group.statusDescription, 'streaming');
      });

      test('returns "stream complete" for finished stream', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          streamStart: createStreamStartEvent(),
          streamEnd: createStreamEndEvent(),
        );
        expect(group.statusDescription, 'stream complete');
      });
    });

    group('requestHeaders', () {
      test('returns headers from request event', () {
        final headers = {'Authorization': 'Bearer token'};
        final group = HttpEventGroup(
          requestId: 'req-1',
          request: createRequestEvent(headers: headers),
        );
        expect(group.requestHeaders, headers);
      });

      test('returns headers from streamStart when no request', () {
        final headers = {'Accept': 'text/event-stream'};
        final group = HttpEventGroup(
          requestId: 'req-1',
          streamStart: createStreamStartEvent(headers: headers),
        );
        expect(group.requestHeaders, headers);
      });

      test('returns empty map when neither request nor streamStart', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          response: createResponseEvent(),
        );
        expect(group.requestHeaders, isEmpty);
      });
    });

    group('requestBody', () {
      test('returns body from request event', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          request: createRequestEvent(body: '{"prompt":"hello"}'),
        );
        expect(group.requestBody, '{"prompt":"hello"}');
      });

      test('returns body from streamStart when no request', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          streamStart: createStreamStartEvent(body: '{"stream":true}'),
        );
        expect(group.requestBody, '{"stream":true}');
      });

      test('returns null when neither request nor streamStart', () {
        final group = HttpEventGroup(
          requestId: 'req-1',
          response: createResponseEvent(),
        );
        expect(group.requestBody, isNull);
      });
    });

    group('copyWith', () {
      test('copies all specified fields', () {
        final original = HttpEventGroup(
          requestId: 'req-1',
          request: createRequestEvent(),
        );
        final response = createResponseEvent(statusCode: 201);
        final updated = original.copyWith(response: response);
        expect(updated.requestId, 'req-1');
        expect(updated.request, original.request);
        expect(updated.response, response);
      });

      test('keeps existing fields when not specified', () {
        final request = createRequestEvent();
        final original = HttpEventGroup(requestId: 'req-1', request: request);
        final updated = original.copyWith();
        expect(updated.request, request);
        expect(updated.response, isNull);
        expect(updated.error, isNull);
      });

      test('can override with new streamStart and streamEnd', () {
        final original = HttpEventGroup(
          requestId: 'req-1',
          streamStart: createStreamStartEvent(),
        );
        final streamEnd = createStreamEndEvent(body: 'data: {}');
        final updated = original.copyWith(streamEnd: streamEnd);
        expect(updated.streamStart, original.streamStart);
        expect(updated.streamEnd, streamEnd);
      });
    });
  });
}
