import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/models/sse_event_parser.dart';

void main() {
  group('sseEventSummary', () {
    test('returns delta for TEXT_MESSAGE_CONTENT', () {
      const event = SseEvent(
        type: 'TEXT_MESSAGE_CONTENT',
        payload: {'type': 'TEXT_MESSAGE_CONTENT', 'delta': 'hello'},
      );
      expect(sseEventSummary(event), 'hello');
    });

    test('returns role for TEXT_MESSAGE_START', () {
      const event = SseEvent(
        type: 'TEXT_MESSAGE_START',
        payload: {'type': 'TEXT_MESSAGE_START', 'role': 'assistant'},
      );
      expect(sseEventSummary(event), 'role: assistant');
    });

    test('returns messageId for TEXT_MESSAGE_END', () {
      const event = SseEvent(
        type: 'TEXT_MESSAGE_END',
        payload: {'type': 'TEXT_MESSAGE_END', 'messageId': 'm1'},
      );
      expect(sseEventSummary(event), 'messageId: m1');
    });

    test('returns tool name for TOOL_CALL_START', () {
      const event = SseEvent(
        type: 'TOOL_CALL_START',
        payload: {'type': 'TOOL_CALL_START', 'toolCallName': 'search'},
      );
      expect(sseEventSummary(event), 'search');
    });

    test('returns delta for TOOL_CALL_ARGS', () {
      const event = SseEvent(
        type: 'TOOL_CALL_ARGS',
        payload: {'type': 'TOOL_CALL_ARGS', 'delta': '{"q":'},
      );
      expect(sseEventSummary(event), '{"q":');
    });

    test('returns toolCallId for TOOL_CALL_END', () {
      const event = SseEvent(
        type: 'TOOL_CALL_END',
        payload: {'type': 'TOOL_CALL_END', 'toolCallId': 'tc1'},
      );
      expect(sseEventSummary(event), 'toolCallId: tc1');
    });

    test('truncates long TOOL_CALL_RESULT content', () {
      final longContent = 'x' * 100;
      final event = SseEvent(
        type: 'TOOL_CALL_RESULT',
        payload: {'type': 'TOOL_CALL_RESULT', 'content': longContent},
      );
      final summary = sseEventSummary(event);
      expect(summary.length, 53); // 50 + '...'
      expect(summary, endsWith('...'));
    });

    test('returns short TOOL_CALL_RESULT content unchanged', () {
      const event = SseEvent(
        type: 'TOOL_CALL_RESULT',
        payload: {'type': 'TOOL_CALL_RESULT', 'content': 'short result'},
      );
      expect(sseEventSummary(event), 'short result');
    });

    test('returns delta for THINKING_CONTENT', () {
      const event = SseEvent(
        type: 'THINKING_CONTENT',
        payload: {'type': 'THINKING_CONTENT', 'delta': 'thinking...'},
      );
      expect(sseEventSummary(event), 'thinking...');
    });

    test('returns (object) for STATE_SNAPSHOT', () {
      const event = SseEvent(
        type: 'STATE_SNAPSHOT',
        payload: {'type': 'STATE_SNAPSHOT'},
      );
      expect(sseEventSummary(event), '(object)');
    });

    test('returns (object) for STATE_DELTA', () {
      const event = SseEvent(
        type: 'STATE_DELTA',
        payload: {'type': 'STATE_DELTA'},
      );
      expect(sseEventSummary(event), '(object)');
    });

    test('returns empty for RUN_STARTED', () {
      const event = SseEvent(
        type: 'RUN_STARTED',
        payload: {'type': 'RUN_STARTED'},
      );
      expect(sseEventSummary(event), isEmpty);
    });

    test('returns empty for RUN_FINISHED', () {
      const event = SseEvent(
        type: 'RUN_FINISHED',
        payload: {'type': 'RUN_FINISHED'},
      );
      expect(sseEventSummary(event), isEmpty);
    });

    test('returns error message for RUN_ERROR', () {
      const event = SseEvent(
        type: 'RUN_ERROR',
        payload: {'type': 'RUN_ERROR', 'message': 'Timeout'},
      );
      expect(sseEventSummary(event), 'Timeout');
    });

    test('returns empty for unknown event types', () {
      const event = SseEvent(
        type: 'UNKNOWN_TYPE',
        payload: {'type': 'UNKNOWN_TYPE'},
      );
      expect(sseEventSummary(event), isEmpty);
    });
  });

  group('parseSseEvents', () {
    test('parses well-formed data lines', () {
      const body = 'data: {"type":"RUN_STARTED","threadId":"t1","runId":"r1"}\n'
          '\n'
          'data: {"type":"RUN_FINISHED","threadId":"t1","runId":"r1"}\n';
      final result = parseSseEvents(body);
      expect(result.events, hasLength(2));
      expect(result.events[0].type, 'RUN_STARTED');
      expect(result.events[0].payload['threadId'], 't1');
      expect(result.events[1].type, 'RUN_FINISHED');
      expect(result.wasTruncated, isFalse);
    });

    test('skips malformed lines', () {
      const body = 'data: {"type":"RUN_STARTED"}\n'
          'not a data line\n'
          'data: not json\n'
          'data: {"type":"RUN_FINISHED"}\n';
      final result = parseSseEvents(body);
      expect(result.events, hasLength(2));
      expect(result.events[0].type, 'RUN_STARTED');
      expect(result.events[1].type, 'RUN_FINISHED');
    });

    test('detects truncation marker', () {
      const body = '[EARLIER CONTENT DROPPED]\n'
          'data: {"type":"TEXT_MESSAGE_END","messageId":"m1"}\n';
      final result = parseSseEvents(body);
      expect(result.wasTruncated, isTrue);
      expect(result.events, hasLength(1));
    });

    test('returns empty for empty body', () {
      final result = parseSseEvents('');
      expect(result.events, isEmpty);
      expect(result.wasTruncated, isFalse);
    });

    test('returns empty for non-SSE content', () {
      const body = '{"error": "not found"}';
      final result = parseSseEvents(body);
      expect(result.events, isEmpty);
    });

    test('handles data lines without trailing newline', () {
      const body = 'data: {"type":"RUN_STARTED"}';
      final result = parseSseEvents(body);
      expect(result.events, hasLength(1));
    });

    test('preserves event payload fields', () {
      const body =
          'data: {"type":"TEXT_MESSAGE_CONTENT","messageId":"m1","delta":"hello"}\n';
      final result = parseSseEvents(body);
      expect(result.events[0].payload['messageId'], 'm1');
      expect(result.events[0].payload['delta'], 'hello');
    });
  });
}
