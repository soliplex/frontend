import 'dart:async';
import 'dart:collection';

import 'package:soliplex_client/src/errors/exceptions.dart';
import 'package:soliplex_client/src/http/concurrency_observer.dart';
import 'package:soliplex_client/src/http/http_redactor.dart';
import 'package:soliplex_client/src/http/http_response.dart';
import 'package:soliplex_client/src/http/soliplex_http_client.dart';
import 'package:soliplex_client/src/utils/cancel_token.dart';

/// HTTP client decorator that caps in-flight requests at [maxConcurrent].
///
/// Excess requests queue in FIFO order and dispatch as earlier requests
/// release their slots. Queued stream requests drop out of the queue
/// immediately when their [CancelToken] fires — no slot is acquired.
///
/// Emits [HttpConcurrencyWaitEvent] to observers on every slot
/// acquisition, including acquisitions with `waitDuration == 0`.
///
/// ## Streams
///
/// [requestStream] holds its slot for the response body's entire
/// lifetime — released when the body stream completes, errors, or is
/// cancelled. This accurately models what the upstream sees (an open
/// connection).
///
/// ## Observer correlation
///
/// The [HttpConcurrencyWaitEvent.requestId] is generated inside this
/// decorator and does NOT correlate with the `requestId` used by
/// other HTTP observers for the same logical request. Observers that
/// need cross-layer correlation should match by URI + timestamp.
///
/// ## Decorator order
///
/// Place below `AuthenticatedHttpClient` so queued requests don't hold
/// stale tokens, and above `ObservableHttpClient` so each wire attempt
/// is observed individually.
///
/// ```text
/// Refreshing -> Authenticated -> Concurrency -> Observable -> Platform
/// ```
class ConcurrencyLimitingHttpClient implements SoliplexHttpClient {
  /// Creates a concurrency-limiting HTTP client.
  ///
  /// - [inner]: The wrapped HTTP client.
  /// - [maxConcurrent]: Maximum in-flight requests. Must be at least 1.
  ///   Sized to match the upstream's connection limit.
  /// - [observers]: Observers notified of queue-wait events.
  /// - [generateRequestId]: Optional ID generator; defaults to a
  ///   per-instance timestamp+counter scheme.
  /// - [clock]: Test injection point for deterministic `waitDuration`.
  ConcurrencyLimitingHttpClient({
    required SoliplexHttpClient inner,
    required this.maxConcurrent,
    List<ConcurrencyObserver> observers = const [],
    String Function()? generateRequestId,
    DateTime Function()? clock,
  })  : _inner = inner,
        _observers = List.unmodifiable(observers),
        _overrideGenerateRequestId = generateRequestId,
        _clock = clock ?? DateTime.now,
        _semaphore = _Semaphore(maxConcurrent) {
    if (maxConcurrent < 1) {
      throw RangeError.range(maxConcurrent, 1, null, 'maxConcurrent');
    }
  }

  final SoliplexHttpClient _inner;
  final List<ConcurrencyObserver> _observers;
  final String Function()? _overrideGenerateRequestId;
  final DateTime Function() _clock;
  final _Semaphore _semaphore;
  int _counter = 0;

  /// Maximum in-flight requests.
  final int maxConcurrent;

  String _generateRequestId() =>
      _overrideGenerateRequestId?.call() ??
      'cc-${DateTime.now().millisecondsSinceEpoch}-${_counter++}';

  /// Performs a one-shot HTTP request, respecting the concurrency cap.
  ///
  /// [SoliplexHttpClient.request] has no `CancelToken`, so queued
  /// non-stream requests cannot be cancelled at this layer — they wait
  /// for their slot, dispatch, and can only be cancelled by a timeout
  /// on the inner client. For cancel-aware behavior use [requestStream].
  @override
  Future<HttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    final requestId = _generateRequestId();
    final enqueuedAt = _clock();
    final depthAtEnqueue = _semaphore.inUseCount + _semaphore.waitingCount;

    final outcome = await _semaphore.acquire();

    final acquiredAt = _clock();
    _emitConcurrencyWait(
      requestId: requestId,
      uri: uri,
      timestamp: acquiredAt,
      waitDuration: outcome == _AcquireOutcome.queued
          ? acquiredAt.difference(enqueuedAt)
          : Duration.zero,
      queueDepthAtEnqueue: depthAtEnqueue,
    );

    try {
      return await _inner.request(
        method,
        uri,
        headers: headers,
        body: body,
        timeout: timeout,
      );
    } finally {
      _semaphore.release();
    }
  }

  /// Acquires a semaphore slot and delegates to the inner client. The
  /// returned body stream is wrapped so the slot is released when the
  /// body completes, errors, or is cancelled.
  ///
  /// **Precondition:** callers MUST listen to the returned
  /// [StreamedHttpResponse.body]. An unlistened body stream will hold
  /// the semaphore slot indefinitely, starving other requests.
  @override
  Future<StreamedHttpResponse> requestStream(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    CancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();

    final requestId = _generateRequestId();
    final enqueuedAt = _clock();
    final depthAtEnqueue = _semaphore.inUseCount + _semaphore.waitingCount;

    final outcome = await _semaphore.acquire(cancelToken: cancelToken);

    StreamedHttpResponse response;
    try {
      cancelToken?.throwIfCancelled();

      final acquiredAt = _clock();
      _emitConcurrencyWait(
        requestId: requestId,
        uri: uri,
        timestamp: acquiredAt,
        waitDuration: outcome == _AcquireOutcome.queued
            ? acquiredAt.difference(enqueuedAt)
            : Duration.zero,
        queueDepthAtEnqueue: depthAtEnqueue,
      );

      response = await _inner.requestStream(
        method,
        uri,
        headers: headers,
        body: body,
        cancelToken: cancelToken,
      );
    } on Object {
      _semaphore.release();
      rethrow;
    }

    return StreamedHttpResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      body: _wrapBodyWithRelease(response.body),
    );
  }

  /// Wraps a body stream so the semaphore slot is released when the
  /// stream completes, errors, or is cancelled.
  ///
  /// Uses `sync: true` to avoid a per-chunk microtask hop on high-rate
  /// byte streams (e.g., SSE). Backpressure is propagated by the
  /// explicit `onPause`/`onResume` forwarding below, not by the sync
  /// mode.
  Stream<List<int>> _wrapBodyWithRelease(Stream<List<int>> source) {
    var released = false;
    void releaseOnce() {
      if (!released) {
        released = true;
        _semaphore.release();
      }
    }

    late StreamController<List<int>> controller;
    StreamSubscription<List<int>>? subscription;

    controller = StreamController<List<int>>(
      sync: true,
      onListen: () {
        subscription = source.listen(
          controller.add,
          onError: (Object error, StackTrace stackTrace) {
            releaseOnce();
            controller.addError(error, stackTrace);
          },
          onDone: () {
            releaseOnce();
            controller.close();
          },
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () {
        releaseOnce();
        return subscription?.cancel();
      },
    );

    return controller.stream;
  }

  @override
  void close() => _inner.close();

  void _emitConcurrencyWait({
    required String requestId,
    required Uri uri,
    required DateTime timestamp,
    required Duration waitDuration,
    required int queueDepthAtEnqueue,
  }) {
    if (_observers.isEmpty) return;

    final redactedUri = HttpRedactor.redactUri(uri);
    final event = HttpConcurrencyWaitEvent(
      requestId: requestId,
      timestamp: timestamp,
      uri: redactedUri,
      waitDuration: waitDuration,
      queueDepthAtEnqueue: queueDepthAtEnqueue,
      slotsInUseAfterAcquire: _semaphore.inUseCount,
    );

    for (final observer in _observers) {
      try {
        observer.onConcurrencyWait(event);
      } on Object catch (error, stackTrace) {
        // Observer failures must not disrupt the request flow, but
        // surface the error in debug so a broken observer is visible.
        assert(
          () {
            // ignore: avoid_print
            print('ConcurrencyObserver ${observer.runtimeType} threw: '
                '$error\n$stackTrace');
            return true;
          }(),
          'observer logging assert',
        );
      }
    }
  }
}

/// Outcome of a semaphore acquisition — whether the caller was queued
/// or acquired a permit immediately.
enum _AcquireOutcome { immediate, queued }

/// Cancel-aware FIFO semaphore.
///
/// [acquire] returns immediately if a permit is available; otherwise
/// the caller is queued. If a [CancelToken] is passed and fires while
/// the caller is queued, the completer is removed from the queue and
/// completed with a [CancelledException] — no permit is acquired.
class _Semaphore {
  _Semaphore(this.maxCount) : _available = maxCount;

  final int maxCount;
  int _available;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  int get inUseCount => maxCount - _available;

  int get waitingCount => _waiters.length;

  /// Returns [_AcquireOutcome.queued] if the caller had to wait, or
  /// [_AcquireOutcome.immediate] if a permit was available.
  Future<_AcquireOutcome> acquire({CancelToken? cancelToken}) {
    if (_available > 0) {
      _available--;
      return Future<_AcquireOutcome>.value(_AcquireOutcome.immediate);
    }
    cancelToken?.throwIfCancelled();

    final completer = Completer<void>();
    _waiters.add(completer);

    if (cancelToken != null) {
      // The callback runs as a single synchronous block with no await,
      // so the isCompleted check and subsequent completeError cannot be
      // interleaved by a concurrent release() — Dart microtasks never
      // preempt synchronous execution.
      cancelToken.whenCancelled.then((_) {
        if (!completer.isCompleted) {
          _waiters.remove(completer);
          completer.completeError(
            CancelledException(reason: cancelToken.reason),
          );
        }
      });
    }

    return completer.future.then((_) => _AcquireOutcome.queued);
  }

  void release() {
    // Skip waiters that were already completed by CancelToken — handing
    // them the permit would waste it (the caller already threw).
    while (_waiters.isNotEmpty) {
      final next = _waiters.removeFirst();
      if (!next.isCompleted) {
        next.complete();
        return;
      }
    }
    _available++;
  }
}
