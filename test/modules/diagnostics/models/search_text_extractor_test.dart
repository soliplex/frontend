import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/models/search_text_extractor.dart';

import '../../../helpers/http_event_factories.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/models/http_event_group.dart';

void main() {
  group('countMatches', () {
    test('counts case-insensitive occurrences', () {
      expect(countMatches('Hello hello HELLO', 'hello'), 3);
    });

    test('returns 0 for empty query', () {
      expect(countMatches('some text', ''), 0);
    });

    test('returns 0 for empty text', () {
      expect(countMatches('', 'query'), 0);
    });

    test('counts non-overlapping matches', () {
      expect(countMatches('aaa', 'aa'), 1);
    });

    test('returns 0 when no match', () {
      expect(countMatches('hello world', 'xyz'), 0);
    });

    test('counts multiple non-overlapping matches', () {
      expect(countMatches('abcabc', 'abc'), 2);
    });
  });

  group('extractRequestText', () {
    test('includes method and uri', () {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(
          method: 'POST',
          uri: Uri.parse('http://localhost/api/v1/runs'),
        ),
      );
      final text = extractRequestText(group);
      expect(text, contains('POST'));
      expect(text, contains('/api/v1/runs'));
    });

    test('includes headers', () {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(
          headers: {'Content-Type': 'application/json'},
        ),
      );
      final text = extractRequestText(group);
      expect(text, contains('Content-Type'));
      expect(text, contains('application/json'));
    });

    test('includes body', () {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(body: '{"prompt":"hello"}'),
      );
      final text = extractRequestText(group);
      expect(text, contains('prompt'));
      expect(text, contains('hello'));
    });

    test('returns method label SSE for streams', () {
      final group = HttpEventGroup(
        requestId: 'req-1',
        streamStart: createStreamStartEvent(method: 'POST'),
      );
      final text = extractRequestText(group);
      expect(text, contains('SSE'));
    });
  });

  group('extractResponseText', () {
    test('includes status code', () {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(),
        response: createResponseEvent(statusCode: 201),
      );
      final text = extractResponseText(group);
      expect(text, contains('201'));
    });

    test('includes reason phrase when present', () {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(),
        response: createResponseEvent(reasonPhrase: 'Created'),
      );
      final text = extractResponseText(group);
      expect(text, contains('Created'));
    });

    test('includes response headers', () {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(),
        response: createResponseEvent(
          headers: {'Content-Type': 'application/json'},
        ),
      );
      final text = extractResponseText(group);
      expect(text, contains('Content-Type'));
    });

    test('includes response body', () {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(),
        response: createResponseEvent(body: '{"result":"ok"}'),
      );
      final text = extractResponseText(group);
      expect(text, contains('result'));
    });

    test('includes error message', () {
      final group = HttpEventGroup(
        requestId: 'req-1',
        error: createErrorEvent(),
      );
      final text = extractResponseText(group);
      expect(text, contains('Connection failed'));
    });

    test('includes stream body', () {
      final group = HttpEventGroup(
        requestId: 'req-1',
        streamStart: createStreamStartEvent(),
        streamEnd: createStreamEndEvent(body: 'data: {"type":"RUN_STARTED"}\n'),
      );
      final text = extractResponseText(group);
      expect(text, contains('RUN_STARTED'));
    });

    test('returns empty when no response data', () {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(),
      );
      final text = extractResponseText(group);
      expect(text, isEmpty);
    });
  });

  group('extractOverviewText', () {
    test('includes request body', () {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(body: '{"prompt":"test"}'),
        response: createResponseEvent(),
      );
      final text = extractOverviewText(group);
      expect(text, contains('prompt'));
    });

    test('includes accumulated SSE text for streams', () {
      final sseBody =
          'data: {"type":"TEXT_MESSAGE_START","messageId":"m1","role":"assistant"}\n'
          'data: {"type":"TEXT_MESSAGE_CONTENT","messageId":"m1","delta":"Hello world"}\n'
          'data: {"type":"TEXT_MESSAGE_END","messageId":"m1"}\n';
      final group = HttpEventGroup(
        requestId: 'req-1',
        streamStart: createStreamStartEvent(),
        streamEnd: createStreamEndEvent(body: sseBody),
      );
      final text = extractOverviewText(group);
      expect(text, contains('Hello world'));
    });

    test('includes tool call name and args in stream overview', () {
      final sseBody =
          'data: {"type":"TOOL_CALL_START","toolCallId":"tc1","toolCallName":"search"}\n'
          'data: {"type":"TOOL_CALL_ARGS","toolCallId":"tc1","delta":"{\\"q\\":\\"foo\\"}"}\n'
          'data: {"type":"TOOL_CALL_END","toolCallId":"tc1"}\n';
      final group = HttpEventGroup(
        requestId: 'req-1',
        streamStart: createStreamStartEvent(),
        streamEnd: createStreamEndEvent(body: sseBody),
      );
      final text = extractOverviewText(group);
      expect(text, contains('search'));
    });

    test('includes response body for regular requests', () {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(),
        response: createResponseEvent(body: '{"data":"value"}'),
      );
      final text = extractOverviewText(group);
      expect(text, contains('data'));
      expect(text, contains('value'));
    });

    test('returns empty string when no body and no stream', () {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(),
      );
      final text = extractOverviewText(group);
      expect(text, isEmpty);
    });
  });
}
