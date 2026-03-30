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
