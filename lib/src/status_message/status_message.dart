import 'package:flutter/foundation.dart' show immutable;

enum MessageIntent { info, warning }

enum MessageCategory { general, maintenance }

@immutable
class MessageWindow {
  MessageWindow({required this.start, required this.end})
      : assert(start.isUtc && end.isUtc, 'window bounds must be UTC');
  final DateTime start;
  final DateTime end;

  /// False when [end] precedes [start] — a malformed operator window. The
  /// message is still shown (the invalid range is flagged in error color and
  /// logged) rather than silently dropped.
  bool get isValid => !end.isBefore(start);

  @override
  bool operator ==(Object other) =>
      other is MessageWindow && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

@immutable
class StatusMessage {
  const StatusMessage({
    required this.id,
    required this.title,
    required this.body,
    required this.intent,
    required this.category,
    this.window,
  }) : assert(
          id.length > 0 && title.length > 0 && body.length > 0,
          'id, title, and body must be non-empty',
        );

  final String id;
  final String title;
  final String body;
  final MessageIntent intent;
  final MessageCategory category;
  final MessageWindow? window;

  factory StatusMessage.fromJson(Map<String, dynamic> json) {
    String requireString(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('status message: missing or invalid "$key"');
      }
      return value;
    }

    // A present-but-malformed window (not an object, unparseable bounds, or a
    // non-UTC bound that would silently shift per viewer) degrades to null —
    // the message still shows, windowless — rather than discarding the whole
    // announcement. The fetcher warns so the operator can spot the mistake.
    // Only id/title/body are load-bearing enough to reject the message.
    MessageWindow? parseWindow() {
      final raw = json['window'];
      if (raw is! Map) return null;
      final DateTime start;
      final DateTime end;
      try {
        start = DateTime.parse(raw['start'] as String);
        end = DateTime.parse(raw['end'] as String);
      } on Object {
        return null;
      }
      if (!start.isUtc || !end.isUtc) return null;
      return MessageWindow(start: start, end: end);
    }

    return StatusMessage(
      id: requireString('id'),
      title: requireString('title'),
      body: requireString('body'),
      intent: MessageIntent.values.asNameMap()[json['intent']] ??
          MessageIntent.info,
      category: MessageCategory.values.asNameMap()[json['category']] ??
          MessageCategory.general,
      window: parseWindow(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StatusMessage &&
      other.id == id &&
      other.title == title &&
      other.body == body &&
      other.intent == intent &&
      other.category == category &&
      other.window == window;

  @override
  int get hashCode => Object.hash(id, title, body, intent, category, window);
}
