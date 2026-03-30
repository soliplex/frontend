import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/models/sse_event_parser.dart';

void main() {
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
