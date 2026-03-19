import 'package:soliplex_agent/soliplex_agent.dart';

/// Collects HTTP events for the network inspector UI.
class NetworkInspector implements HttpObserver {
  final List<HttpEvent> events = [];

  @override
  void onRequest(HttpRequestEvent event) => events.add(event);

  @override
  void onResponse(HttpResponseEvent event) => events.add(event);

  @override
  void onError(HttpErrorEvent event) => events.add(event);

  @override
  void onStreamStart(HttpStreamStartEvent event) => events.add(event);

  @override
  void onStreamEnd(HttpStreamEndEvent event) => events.add(event);
}
