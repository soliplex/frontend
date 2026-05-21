import 'package:soliplex_agent/soliplex_agent.dart';

import 'http_event_group.dart';

List<HttpEventGroup> groupHttpEvents(List<HttpEvent> events) {
  final groups = <String, HttpEventGroup>{};

  for (final event in events) {
    final id = event.requestId;
    final existing = groups[id] ?? HttpEventGroup(requestId: id);

    groups[id] = switch (event) {
      HttpRequestEvent() => existing.copyWith(request: event),
      HttpResponseEvent() => existing.copyWith(response: event),
      HttpErrorEvent() => existing.copyWith(error: event),
      HttpStreamStartEvent() => existing.copyWith(streamStart: event),
      HttpStreamEndEvent() => existing.copyWith(streamEnd: event),
      _ => existing,
    };
  }

  // Orphan groups (response or streamEnd whose request/streamStart was
  // evicted from the inspector's bounded buffer) have no sortable
  // timestamp and would throw from [HttpEventGroup.timestamp]. They sit
  // invisibly in the buffer until FIFO eviction removes them too.
  final sorted = groups.values.where((g) => g.hasTimestamp).toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return sorted;
}
