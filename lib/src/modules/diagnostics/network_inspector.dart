import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

/// Collects HTTP events for the network inspector UI.
///
/// Events are bounded per list: on overflow, the oldest event is dropped
/// so a long-running dev session cannot grow memory without bound.
class NetworkInspector
    with ChangeNotifier
    implements HttpObserver, ConcurrencyObserver {
  NetworkInspector({int maxEvents = 1000})
      : _maxEvents = maxEvents > 0
            ? maxEvents
            : throw ArgumentError.value(
                maxEvents,
                'maxEvents',
                'must be positive',
              );

  final int _maxEvents;
  final ListQueue<HttpEvent> _events = ListQueue<HttpEvent>();
  final ListQueue<ConcurrencyWaitEvent> _concurrencyEvents =
      ListQueue<ConcurrencyWaitEvent>();
  bool _disposed = false;

  List<HttpEvent> get events => List.unmodifiable(_events);

  List<ConcurrencyWaitEvent> get concurrencyEvents =>
      List.unmodifiable(_concurrencyEvents);

  void clear() {
    if (_disposed) return;
    _events.clear();
    _concurrencyEvents.clear();
    notifyListeners();
  }

  void _add(HttpEvent event) {
    if (_disposed) return;
    _events.addLast(event);
    if (_events.length > _maxEvents) _events.removeFirst();
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
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
  void onConcurrencyWait(ConcurrencyWaitEvent event) {
    if (_disposed) return;
    _concurrencyEvents.addLast(event);
    if (_concurrencyEvents.length > _maxEvents) {
      _concurrencyEvents.removeFirst();
    }
    notifyListeners();
  }
}
