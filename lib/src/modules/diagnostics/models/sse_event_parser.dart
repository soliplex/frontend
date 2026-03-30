import 'dart:convert';

class SseEvent {
  const SseEvent({required this.type, required this.payload});

  final String type;
  final Map<String, dynamic> payload;
}

class SseParseResult {
  const SseParseResult({required this.events, required this.wasTruncated});

  final List<SseEvent> events;
  final bool wasTruncated;
}

const _truncationMarker = '[EARLIER CONTENT DROPPED]';
const _dataPrefix = 'data: ';

/// Returns a brief summary string for an [SseEvent], used in the events list view.
String sseEventSummary(SseEvent event) {
  final payload = event.payload;
  return switch (event.type) {
    'TEXT_MESSAGE_CONTENT' => payload['delta'] as String? ?? '',
    'TEXT_MESSAGE_START' => 'role: ${payload['role'] as String? ?? '?'}',
    'TEXT_MESSAGE_END' => 'messageId: ${payload['messageId'] ?? '?'}',
    'TOOL_CALL_START' => payload['toolCallName'] as String? ?? '?',
    'TOOL_CALL_ARGS' => payload['delta'] as String? ?? '',
    'TOOL_CALL_END' => 'toolCallId: ${payload['toolCallId'] ?? '?'}',
    'TOOL_CALL_RESULT' => _truncate(payload['content'] as String? ?? '', 50),
    'THINKING_CONTENT' => payload['delta'] as String? ?? '',
    'STATE_SNAPSHOT' || 'STATE_DELTA' => '(object)',
    'RUN_STARTED' || 'RUN_FINISHED' => '',
    'RUN_ERROR' => payload['message'] as String? ?? '',
    _ => '',
  };
}

String _truncate(String text, int maxLength) {
  if (text.length <= maxLength) return text;
  return '${text.substring(0, maxLength)}...';
}

SseParseResult parseSseEvents(String body) {
  if (body.isEmpty) {
    return const SseParseResult(events: [], wasTruncated: false);
  }

  final wasTruncated = body.startsWith(_truncationMarker);
  final events = <SseEvent>[];

  for (final line in body.split('\n')) {
    if (!line.startsWith(_dataPrefix)) continue;
    final jsonStr = line.substring(_dataPrefix.length);
    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final type = json['type'] as String?;
      if (type != null) {
        events.add(SseEvent(type: type, payload: json));
      }
    } on FormatException {
      // Skip malformed JSON lines.
    } on TypeError {
      // Skip lines where JSON isn't a Map.
    }
  }

  return SseParseResult(events: events, wasTruncated: wasTruncated);
}
