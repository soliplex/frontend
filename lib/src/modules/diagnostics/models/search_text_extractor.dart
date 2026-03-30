import 'event_accumulator.dart';
import 'http_event_group.dart';
import 'sse_event_parser.dart';

/// Returns all request-side text from [group] as a single searchable string.
String extractRequestText(HttpEventGroup group) {
  final parts = <String>[];
  parts.add(group.methodLabel);
  parts.add(group.uri.toString());
  final headers = group.requestHeaders;
  for (final e in headers.entries) {
    parts.add('${e.key}: ${e.value}');
  }
  final body = group.requestBody;
  if (body != null) parts.add(HttpEventGroup.formatBody(body));
  return parts.join('\n');
}

/// Returns all response-side text from [group] as a single searchable string.
String extractResponseText(HttpEventGroup group) {
  final parts = <String>[];
  final resp = group.response;
  if (resp != null) {
    parts.add('${resp.statusCode}');
    if (resp.reasonPhrase != null) parts.add(resp.reasonPhrase!);
    final headers = resp.headers;
    if (headers != null) {
      for (final e in headers.entries) {
        parts.add('${e.key}: ${e.value}');
      }
    }
    if (resp.body != null) parts.add(HttpEventGroup.formatBody(resp.body));
  }
  final error = group.error;
  if (error != null) {
    parts.add(error.exception.message);
  }
  final streamEnd = group.streamEnd;
  if (streamEnd != null && streamEnd.body != null) {
    parts.add(streamEnd.body!);
  }
  return parts.join('\n');
}

/// Returns all overview-tab text from [group] as a single searchable string.
String extractOverviewText(HttpEventGroup group) {
  final buf = StringBuffer();
  final body = group.requestBody;
  if (body != null) buf.write(HttpEventGroup.formatBody(body));

  if (group.isStream && group.streamEnd?.body != null) {
    final rawBody = group.streamEnd!.body!;
    buf.write(rawBody);
    final parsed = parseSseEvents(rawBody);
    final run = accumulateEvents(parsed.events);
    for (final entry in run.entries) {
      switch (entry) {
        case MessageEntry(:final text):
          buf.write(text);
        case ToolCallEntry(:final toolName, :final args):
          buf.write(toolName);
          buf.write(args);
        case ToolResultEntry(:final content):
          buf.write(content);
        case ThinkingEntry(:final text):
          buf.write(text);
        case RunStatusEntry(:final message):
          if (message != null) buf.write(message);
        case StateEntry():
          break;
      }
    }
  } else if (!group.isStream && group.response?.body != null) {
    buf.write(HttpEventGroup.formatBody(group.response!.body));
  }
  return buf.toString();
}

/// Counts case-insensitive occurrences of [query] in [text].
int countMatches(String text, String query) {
  if (query.isEmpty || text.isEmpty) return 0;
  final lowerQuery = query.toLowerCase();
  final lowerText = text.toLowerCase();
  var count = 0;
  var index = 0;
  while (true) {
    index = lowerText.indexOf(lowerQuery, index);
    if (index == -1) break;
    count++;
    index += lowerQuery.length;
  }
  return count;
}
