import 'package:meta/meta.dart';

/// Observer interface for the concurrency limiter.
///
/// Implementations receive [HttpConcurrencyWaitEvent] notifications when a
/// request acquires a slot from the semaphore.
///
/// Kept separate from `HttpObserver` because Dart `implements` does not
/// carry default method bodies, so adding a method to `HttpObserver`
/// would be a breaking change for every implementer. An observer that
/// wants both HTTP and concurrency visibility can implement both
/// interfaces side-by-side.
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
/// [waitDuration] is zero for requests that acquired immediately (no
/// queue contention).
///
/// Note: [requestId] is generated inside the limiter and does NOT
/// correlate with the `requestId` that other HTTP observers use for the
/// same logical request — the limiter and the observable decorator run
/// independent ID generators. Observers that want to correlate events
/// across layers should match by [uri] + [timestamp] proximity.
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

  /// Number of requests already in the system (in-flight + waiting) when
  /// this request arrived. Zero when the system was idle.
  final int queueDepthAtEnqueue;

  /// Number of in-flight slots occupied immediately after this request
  /// acquired its slot. Between 1 and the limiter's configured max.
  final int slotsInUseAfterAcquire;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HttpConcurrencyWaitEvent &&
          requestId == other.requestId &&
          timestamp == other.timestamp &&
          uri == other.uri &&
          waitDuration == other.waitDuration &&
          queueDepthAtEnqueue == other.queueDepthAtEnqueue &&
          slotsInUseAfterAcquire == other.slotsInUseAfterAcquire;

  @override
  int get hashCode => Object.hash(
        requestId,
        timestamp,
        uri,
        waitDuration,
        queueDepthAtEnqueue,
        slotsInUseAfterAcquire,
      );

  @override
  String toString() => 'HttpConcurrencyWaitEvent('
      '$requestId, waited ${waitDuration.inMilliseconds}ms, '
      'depth $queueDepthAtEnqueue, slots $slotsInUseAfterAcquire)';
}
