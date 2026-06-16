import 'package:soliplex_agent/soliplex_agent.dart';

import 'http_event_group.dart';

/// Whether a grouped exchange belongs to [runId] — the group-level twin of
/// [filterEventsByRunId], used by the Network Inspector's run-scope filter.
/// A run id appears as a path segment of the request URL (e.g.
/// `…/threads/{thread}/runs/{runId}`).
bool groupMatchesRun(HttpEventGroup group, String runId) =>
    group.uri.pathSegments.contains(runId);

List<HttpEvent> filterEventsByRunId(List<HttpEvent> events, String runId) {
  final matchingRequestIds = <String>{};
  for (final event in events) {
    final uri = _uriOf(event);
    if (uri != null && uri.pathSegments.contains(runId)) {
      matchingRequestIds.add(event.requestId);
    }
  }

  return events.where((e) => matchingRequestIds.contains(e.requestId)).toList();
}

Uri? _uriOf(HttpEvent event) {
  return switch (event) {
    HttpRequestEvent(:final uri) => uri,
    HttpErrorEvent(:final uri) => uri,
    HttpStreamStartEvent(:final uri) => uri,
    _ => null,
  };
}
