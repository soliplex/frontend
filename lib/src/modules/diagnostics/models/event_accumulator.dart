import 'dart:convert';

import 'sse_event_parser.dart';

sealed class RunEntry {
  const RunEntry();
}

class MessageEntry extends RunEntry {
  const MessageEntry({
    required this.messageId,
    required this.role,
    required this.text,
  });

  final String messageId;
  final String role;
  final String text;
}

class ToolCallEntry extends RunEntry {
  const ToolCallEntry({
    required this.toolCallId,
    required this.toolName,
    required this.args,
  });

  final String toolCallId;
  final String toolName;
  final String args;
}

class ToolResultEntry extends RunEntry {
  const ToolResultEntry({required this.toolCallId, required this.content});

  final String toolCallId;
  final String content;
}

class ThinkingEntry extends RunEntry {
  const ThinkingEntry({required this.text});

  final String text;
}

class StateEntry extends RunEntry {
  const StateEntry({required this.type, required this.data});

  final String type;
  final dynamic data;
}

class RunStatusEntry extends RunEntry {
  const RunStatusEntry({required this.type, this.message});

  final String type;
  final String? message;
}

class AccumulatedRun {
  const AccumulatedRun({required this.entries, required this.isComplete});

  final List<RunEntry> entries;
  final bool isComplete;
}

AccumulatedRun accumulateEvents(List<SseEvent> events) {
  final entries = <RunEntry>[];
  final textBuffers = <String, StringBuffer>{};
  final textRoles = <String, String>{};
  final toolArgBuffers = <String, StringBuffer>{};
  final toolNames = <String, String>{};
  final thinkingBuffer = StringBuffer();
  var inThinking = false;
  var isComplete = false;

  void flushMessage(String messageId) {
    final buffer = textBuffers.remove(messageId);
    final role = textRoles.remove(messageId);
    if (buffer != null) {
      entries.add(MessageEntry(
        messageId: messageId,
        role: role ?? 'assistant',
        text: buffer.toString(),
      ));
    }
  }

  void flushToolCall(String toolCallId) {
    final buffer = toolArgBuffers.remove(toolCallId);
    final name = toolNames.remove(toolCallId);
    if (name != null) {
      final rawArgs = buffer?.toString() ?? '';
      String formattedArgs;
      try {
        final parsed = jsonDecode(rawArgs);
        formattedArgs = const JsonEncoder.withIndent('  ').convert(parsed);
      } on FormatException {
        formattedArgs = rawArgs;
      }
      entries.add(
        ToolCallEntry(
            toolCallId: toolCallId, toolName: name, args: formattedArgs),
      );
    }
  }

  void flushThinking() {
    if (thinkingBuffer.isNotEmpty) {
      entries.add(ThinkingEntry(text: thinkingBuffer.toString()));
      thinkingBuffer.clear();
    }
    inThinking = false;
  }

  for (final event in events) {
    switch (event.type) {
      case 'RUN_STARTED' || 'RUN_FINISHED' || 'RUN_ERROR':
        if (event.type == 'RUN_FINISHED' || event.type == 'RUN_ERROR') {
          isComplete = true;
        }
        entries.add(RunStatusEntry(
          type: event.type,
          message: event.payload['message'] as String?,
        ));
      case 'TEXT_MESSAGE_START':
        final id = event.payload['messageId'] as String? ?? '';
        textBuffers[id] = StringBuffer();
        textRoles[id] = event.payload['role'] as String? ?? 'assistant';
      case 'TEXT_MESSAGE_CONTENT':
        final id = event.payload['messageId'] as String? ?? '';
        textBuffers.putIfAbsent(id, StringBuffer.new);
        textBuffers[id]!.write(event.payload['delta'] as String? ?? '');
      case 'TEXT_MESSAGE_END':
        flushMessage(event.payload['messageId'] as String? ?? '');
      case 'TOOL_CALL_START':
        final id = event.payload['toolCallId'] as String? ?? '';
        toolNames[id] = event.payload['toolCallName'] as String? ?? '';
        toolArgBuffers[id] = StringBuffer();
      case 'TOOL_CALL_ARGS':
        final id = event.payload['toolCallId'] as String? ?? '';
        toolArgBuffers.putIfAbsent(id, StringBuffer.new);
        toolArgBuffers[id]!.write(event.payload['delta'] as String? ?? '');
      case 'TOOL_CALL_END':
        flushToolCall(event.payload['toolCallId'] as String? ?? '');
      case 'TOOL_CALL_RESULT':
        entries.add(ToolResultEntry(
          toolCallId: event.payload['toolCallId'] as String? ?? '',
          content: event.payload['content'] as String? ?? '',
        ));
      case 'THINKING_START':
        inThinking = true;
        thinkingBuffer.clear();
      case 'THINKING_CONTENT':
        if (inThinking) {
          thinkingBuffer.write(event.payload['delta'] as String? ?? '');
        }
      case 'THINKING_END':
        flushThinking();
      case 'STATE_SNAPSHOT':
        entries.add(StateEntry(
            type: 'STATE_SNAPSHOT', data: event.payload['snapshot']));
      case 'STATE_DELTA':
        entries
            .add(StateEntry(type: 'STATE_DELTA', data: event.payload['delta']));
      default:
        break;
    }
  }

  // Flush in-progress items for partial streams.
  for (final id in textBuffers.keys.toList()) {
    flushMessage(id);
  }
  for (final id in toolArgBuffers.keys.toList()) {
    flushToolCall(id);
  }
  if (inThinking) flushThinking();

  return AccumulatedRun(entries: entries, isComplete: isComplete);
}
