import 'package:soliplex_agent/soliplex_agent.dart';

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
    HttpRequestEvent(:final uri) ||
    HttpErrorEvent(:final uri) ||
    HttpStreamStartEvent(:final uri) => uri,
    _ => null,
  };
}
