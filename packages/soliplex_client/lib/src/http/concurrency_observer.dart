import 'package:meta/meta.dart';

/// Observer interface for the concurrency limiter.
///
/// Implementations receive [ConcurrencyWaitEvent] notifications when a
/// request acquires a slot from the semaphore.
///
/// Separate from `HttpObserver` so concurrency events can be added
/// without forcing existing `HttpObserver` implementers to update —
/// Dart `implements` does not forward default method bodies. An
/// observer that wants both HTTP and concurrency visibility can
/// implement both interfaces side-by-side.
// ignore: one_member_abstracts
abstract interface class ConcurrencyObserver {
  /// Called when a request acquires a slot from the concurrency limiter.
  void onConcurrencyWait(ConcurrencyWaitEvent event);
}

/// Event emitted by the concurrency limiter when a request acquires a
/// slot from the semaphore.
///
/// [waitDuration] is zero for requests that acquired immediately (no
/// queue contention).
///
/// This event is not in the `HttpEvent` family — one concurrency slot
/// can span multiple HTTP attempts (original + 401 refresh + retry),
/// so there is no stable one-to-one mapping with `HttpEvent.requestId`.
@immutable
class ConcurrencyWaitEvent {
  /// Creates a concurrency-wait event.
  const ConcurrencyWaitEvent({
    required this.acquisitionId,
    required this.timestamp,
    required this.uri,
    required this.waitDuration,
    required this.queueDepthAtEnqueue,
    required this.slotsInUseAfterAcquire,
  })  : assert(acquisitionId != '', 'acquisitionId must not be empty'),
        assert(
          queueDepthAtEnqueue >= 0,
          'queueDepthAtEnqueue must be non-negative',
        ),
        assert(
          slotsInUseAfterAcquire >= 1,
          'slotsInUseAfterAcquire must be at least 1',
        );

  /// Unique identifier for this slot acquisition. Scoped to the
  /// concurrency layer; does not correlate with `HttpEvent.requestId`
  /// because one acquisition may contain multiple HTTP attempts
  /// (e.g., a 401 triggering a refresh and a retry).
  final String acquisitionId;

  /// When the slot was acquired.
  final DateTime timestamp;

  /// The request URI, with sensitive parts redacted.
  final Uri uri;

  /// Time spent waiting in the queue before acquiring a slot. Zero when
  /// a slot was available immediately.
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
      other is ConcurrencyWaitEvent &&
          acquisitionId == other.acquisitionId &&
          timestamp == other.timestamp &&
          uri == other.uri &&
          waitDuration == other.waitDuration &&
          queueDepthAtEnqueue == other.queueDepthAtEnqueue &&
          slotsInUseAfterAcquire == other.slotsInUseAfterAcquire;

  @override
  int get hashCode => Object.hash(
        acquisitionId,
        timestamp,
        uri,
        waitDuration,
        queueDepthAtEnqueue,
        slotsInUseAfterAcquire,
      );

  @override
  String toString() => 'ConcurrencyWaitEvent('
      '$acquisitionId, waited ${waitDuration.inMilliseconds}ms, '
      'depth $queueDepthAtEnqueue, slots $slotsInUseAfterAcquire)';
}
