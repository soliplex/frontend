import 'package:flutter/foundation.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

/// Collects HTTP events for the network inspector UI.
class NetworkInspector
    with ChangeNotifier
    implements HttpObserver, ConcurrencyObserver {
  final List<HttpEvent> _events = [];
  final List<HttpConcurrencyWaitEvent> _concurrencyEvents = [];
  bool _disposed = false;

  List<HttpEvent> get events => List.unmodifiable(_events);

  List<HttpConcurrencyWaitEvent> get concurrencyEvents =>
      List.unmodifiable(_concurrencyEvents);

  void clear() {
    if (_disposed) return;
    _events.clear();
    _concurrencyEvents.clear();
    notifyListeners();
  }

  void _add(HttpEvent event) {
    if (_disposed) return;
    _events.add(event);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void onRequest(HttpRequestEvent event) => _add(event);

  @override
  void onResponse(HttpResponseEvent event) => _add(event);

  @override
  void onError(HttpErrorEvent event) => _add(event);

  @override
  void onStreamStart(HttpStreamStartEvent event) => _add(event);

  @override
  void onStreamEnd(HttpStreamEndEvent event) => _add(event);

  @override
  void onConcurrencyWait(HttpConcurrencyWaitEvent event) {
    if (_disposed) return;
    _concurrencyEvents.add(event);
    notifyListeners();
  }
}
