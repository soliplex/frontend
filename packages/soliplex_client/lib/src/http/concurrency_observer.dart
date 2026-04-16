import 'package:meta/meta.dart';
// ignore: unused_import
import 'package:soliplex_client/src/http/http_observer.dart';
// ignore: unused_import
import 'package:soliplex_client/src/http/observable_http_client.dart';

/// Observer interface for the concurrency limiter.
///
/// Implementations receive [HttpConcurrencyWaitEvent] notifications when a
/// request acquires a slot from the semaphore. Kept separate from
/// [HttpObserver] so existing observer implementations don't need to
/// change (Dart `implements` strips default method bodies, making
/// additive changes to existing interfaces a breaking change).
///
/// An observer that wants both HTTP and concurrency visibility can
/// `implements HttpObserver, ConcurrencyObserver` side-by-side.
///
/// Example:
/// ```dart
/// class MyInspector implements HttpObserver, ConcurrencyObserver {
///   @override
///   void onRequest(HttpRequestEvent event) { /* ... */ }
///   // ... other HttpObserver methods ...
///
///   @override
///   void onConcurrencyWait(HttpConcurrencyWaitEvent event) {
///     print('Queue wait: ${event.waitDuration}');
///   }
/// }
/// ```
// ignore: one_member_abstracts
abstract interface class ConcurrencyObserver {
  /// Called when a request acquires a slot from the concurrency limiter.
  ///
  /// [event] reports how long the request waited, the queue depth at
  /// enqueue, and the current slots-in-use count.
  void onConcurrencyWait(HttpConcurrencyWaitEvent event);
}

/// Event emitted by the concurrency limiter when a request acquires a
/// slot from the semaphore.
///
/// `waitDuration` is zero for requests that acquired immediately (no
/// queue contention).
///
/// Note: [requestId] is generated inside the limiter and does NOT
/// correlate with the `requestId` that [ObservableHttpClient] generates
/// for the same logical request — the two decorators run independent
/// ID generators. Observers that want to correlate events across layers
/// should match by [uri] + [timestamp] proximity.
@immutable
class HttpConcurrencyWaitEvent {
  /// Creates a concurrency-wait event.
  const HttpConcurrencyWaitEvent({
    required this.requestId,
    required this.timestamp,
    required this.uri,
    required this.waitDuration,
    required this.queueDepthAtEnqueue,
    required this.slotsInUseAfterAcquire,
  });

  /// Unique identifier for this acquisition. Does not correlate with
  /// other HTTP event IDs across decorator layers.
  final String requestId;

  /// When the slot was acquired.
  final DateTime timestamp;

  /// The request URI (with sensitive parts redacted).
  final Uri uri;

  /// Time spent waiting in the queue before acquiring a slot.
  ///
  /// Zero when a slot was available immediately.
  final Duration waitDuration;

  /// Number of requests already queued ahead of this one when it
  /// arrived. Zero when the queue was empty.
  final int queueDepthAtEnqueue;

  /// Number of in-flight slots occupied immediately after this request
  /// acquired its slot. Between 1 and the limiter's configured max.
  final int slotsInUseAfterAcquire;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HttpConcurrencyWaitEvent && requestId == other.requestId;

  @override
  int get hashCode => requestId.hashCode;

  @override
  String toString() => 'HttpConcurrencyWaitEvent('
      '$requestId, waited ${waitDuration.inMilliseconds}ms, '
      'depth $queueDepthAtEnqueue, slots $slotsInUseAfterAcquire)';
}
