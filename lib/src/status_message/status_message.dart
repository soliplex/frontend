import 'package:flutter/foundation.dart' show immutable;

enum MessageIntent { info, warning }

enum MessageCategory { general, maintenance }

@immutable
class MessageWindow {
  const MessageWindow({required this.start, required this.end});
  final DateTime start;
  final DateTime end;
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
  });

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

    MessageWindow? parseWindow() {
      final raw = json['window'];
      if (raw == null) return null;
      if (raw is! Map) {
        throw const FormatException('status message: invalid "window"');
      }
      try {
        return MessageWindow(
          start: DateTime.parse(raw['start'] as String).toUtc(),
          end: DateTime.parse(raw['end'] as String).toUtc(),
        );
      } on Object catch (e) {
        throw FormatException('status message: invalid window bounds: $e');
      }
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
}
