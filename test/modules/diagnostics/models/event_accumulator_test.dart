import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/models/event_accumulator.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/models/sse_event_parser.dart';

void main() {
  group('accumulateEvents', () {
    test('merges text message deltas into single entry', () {
      final events = [
        const SseEvent(type: 'RUN_STARTED', payload: {
          'type': 'RUN_STARTED',
          'threadId': 't1',
          'runId': 'r1',
        }),
        const SseEvent(type: 'TEXT_MESSAGE_START', payload: {
          'type': 'TEXT_MESSAGE_START',
          'messageId': 'm1',
          'role': 'assistant',
        }),
        const SseEvent(type: 'TEXT_MESSAGE_CONTENT', payload: {
          'type': 'TEXT_MESSAGE_CONTENT',
          'messageId': 'm1',
          'delta': 'Hello ',
        }),
        const SseEvent(type: 'TEXT_MESSAGE_CONTENT', payload: {
          'type': 'TEXT_MESSAGE_CONTENT',
          'messageId': 'm1',
          'delta': 'world!',
        }),
        const SseEvent(type: 'TEXT_MESSAGE_END', payload: {
          'type': 'TEXT_MESSAGE_END',
          'messageId': 'm1',
        }),
        const SseEvent(type: 'RUN_FINISHED', payload: {
          'type': 'RUN_FINISHED',
          'threadId': 't1',
          'runId': 'r1',
        }),
      ];
      final run = accumulateEvents(events);
      expect(run.isComplete, isTrue);
      final messages = run.entries.whereType<MessageEntry>().toList();
      expect(messages, hasLength(1));
      expect(messages[0].text, 'Hello world!');
      expect(messages[0].role, 'assistant');
    });

    test('accumulates tool call args', () {
      final events = [
        const SseEvent(type: 'TOOL_CALL_START', payload: {
          'type': 'TOOL_CALL_START',
          'toolCallId': 'tc1',
          'toolCallName': 'search',
          'parentMessageId': 'm1',
        }),
        const SseEvent(type: 'TOOL_CALL_ARGS', payload: {
          'type': 'TOOL_CALL_ARGS',
          'toolCallId': 'tc1',
          'delta': '{"query":',
        }),
        const SseEvent(type: 'TOOL_CALL_ARGS', payload: {
          'type': 'TOOL_CALL_ARGS',
          'toolCallId': 'tc1',
          'delta': ' "hello"}',
        }),
        const SseEvent(type: 'TOOL_CALL_END', payload: {
          'type': 'TOOL_CALL_END',
          'toolCallId': 'tc1',
        }),
      ];
      final run = accumulateEvents(events);
      final toolCalls = run.entries.whereType<ToolCallEntry>().toList();
      expect(toolCalls, hasLength(1));
      expect(toolCalls[0].toolName, 'search');
      expect(toolCalls[0].args, contains('"query"'));
    });

    test('captures tool result', () {
      final events = [
        const SseEvent(type: 'TOOL_CALL_RESULT', payload: {
          'type': 'TOOL_CALL_RESULT',
          'messageId': 'm2',
          'toolCallId': 'tc1',
          'content': 'Search result here',
          'role': 'tool',
        }),
      ];
      final run = accumulateEvents(events);
      final results = run.entries.whereType<ToolResultEntry>().toList();
      expect(results, hasLength(1));
      expect(results[0].content, 'Search result here');
      expect(results[0].toolCallId, 'tc1');
    });

    test('accumulates thinking deltas', () {
      final events = [
        const SseEvent(
            type: 'THINKING_START',
            payload: {'type': 'THINKING_START', 'title': 'Analyzing'}),
        const SseEvent(type: 'THINKING_CONTENT', payload: {
          'type': 'THINKING_CONTENT',
          'delta': 'Let me think...',
        }),
        const SseEvent(type: 'THINKING_CONTENT', payload: {
          'type': 'THINKING_CONTENT',
          'delta': ' about this.',
        }),
        const SseEvent(type: 'THINKING_END', payload: {'type': 'THINKING_END'}),
      ];
      final run = accumulateEvents(events);
      final thinking = run.entries.whereType<ThinkingEntry>().toList();
      expect(thinking, hasLength(1));
      expect(thinking[0].text, 'Let me think... about this.');
    });

    test('handles RUN_ERROR', () {
      final events = [
        const SseEvent(type: 'RUN_STARTED', payload: {'type': 'RUN_STARTED'}),
        const SseEvent(type: 'RUN_ERROR', payload: {
          'type': 'RUN_ERROR',
          'message': 'Timeout',
          'code': 'TIMEOUT',
        }),
      ];
      final run = accumulateEvents(events);
      expect(run.isComplete, isTrue);
      final statuses = run.entries.whereType<RunStatusEntry>().toList();
      final errorEntry = statuses.where((s) => s.type == 'RUN_ERROR').first;
      expect(errorEntry.message, 'Timeout');
    });

    test('handles partial stream with no RUN_FINISHED', () {
      final events = [
        const SseEvent(type: 'RUN_STARTED', payload: {'type': 'RUN_STARTED'}),
        const SseEvent(type: 'TEXT_MESSAGE_START', payload: {
          'type': 'TEXT_MESSAGE_START',
          'messageId': 'm1',
          'role': 'assistant',
        }),
        const SseEvent(type: 'TEXT_MESSAGE_CONTENT', payload: {
          'type': 'TEXT_MESSAGE_CONTENT',
          'messageId': 'm1',
          'delta': 'partial...',
        }),
      ];
      final run = accumulateEvents(events);
      expect(run.isComplete, isFalse);
      final messages = run.entries.whereType<MessageEntry>().toList();
      expect(messages, hasLength(1));
      expect(messages[0].text, 'partial...');
    });

    test('captures state snapshot', () {
      final events = [
        const SseEvent(type: 'STATE_SNAPSHOT', payload: {
          'type': 'STATE_SNAPSHOT',
          'snapshot': {'count': 0},
        }),
      ];
      final run = accumulateEvents(events);
      final states = run.entries.whereType<StateEntry>().toList();
      expect(states, hasLength(1));
      expect(states[0].data, {'count': 0});
    });

    test('orders multiple entries chronologically', () {
      final events = [
        const SseEvent(type: 'RUN_STARTED', payload: {'type': 'RUN_STARTED'}),
        const SseEvent(type: 'TEXT_MESSAGE_START', payload: {
          'type': 'TEXT_MESSAGE_START',
          'messageId': 'm1',
          'role': 'assistant',
        }),
        const SseEvent(type: 'TEXT_MESSAGE_CONTENT', payload: {
          'type': 'TEXT_MESSAGE_CONTENT',
          'messageId': 'm1',
          'delta': 'Hi',
        }),
        const SseEvent(type: 'TEXT_MESSAGE_END', payload: {
          'type': 'TEXT_MESSAGE_END',
          'messageId': 'm1',
        }),
        const SseEvent(type: 'TOOL_CALL_START', payload: {
          'type': 'TOOL_CALL_START',
          'toolCallId': 'tc1',
          'toolCallName': 'search',
        }),
        const SseEvent(type: 'TOOL_CALL_END', payload: {
          'type': 'TOOL_CALL_END',
          'toolCallId': 'tc1',
        }),
        const SseEvent(type: 'RUN_FINISHED', payload: {'type': 'RUN_FINISHED'}),
      ];
      final run = accumulateEvents(events);
      expect(run.entries[0], isA<RunStatusEntry>());
      expect(run.entries[1], isA<MessageEntry>());
      expect(run.entries[2], isA<ToolCallEntry>());
      expect(run.entries[3], isA<RunStatusEntry>());
    });
  });
}
