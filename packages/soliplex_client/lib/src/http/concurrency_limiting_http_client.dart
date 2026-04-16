import 'dart:async';
import 'dart:collection';

import 'package:soliplex_client/src/errors/exceptions.dart';
import 'package:soliplex_client/src/http/concurrency_observer.dart';
import 'package:soliplex_client/src/http/http_diagnostic.dart';
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
/// Emits [ConcurrencyWaitEvent] to observers on every slot
/// acquisition, including acquisitions with `waitDuration == 0`.
///
/// [requestStream] holds its slot for the response body's entire
/// lifetime — released when the body stream completes, errors, or is
/// cancelled. This accurately models what the upstream sees (an open
/// connection).
///
/// Place at the outermost layer of the auth-aware stack so per-request
/// auth work (token fetch, proactive refresh) runs at dispatch time, not
/// at enqueue time — queued requests therefore never hold stale tokens.
class ConcurrencyLimitingHttpClient implements SoliplexHttpClient {
  /// Creates a concurrency-limiting HTTP client.
  ///
  /// - [inner]: The wrapped HTTP client.
  /// - [maxConcurrent]: Maximum in-flight requests. Must be at least 1.
  ///   Sized to match the upstream's connection limit.
  /// - [observers]: Observers notified of queue-wait events.
  /// - [generateAcquisitionId]: Optional ID generator.
  /// - [clock]: Optional clock override (tests only).
  /// - [onDiagnostic]: Handler for contained internal errors.
  ConcurrencyLimitingHttpClient({
    required SoliplexHttpClient inner,
    required int maxConcurrent,
    List<ConcurrencyObserver> observers = const [],
    String Function()? generateAcquisitionId,
    DateTime Function()? clock,
    HttpDiagnosticHandler? onDiagnostic,
  })  : maxConcurrent = maxConcurrent >= 1
            ? maxConcurrent
            : throw RangeError.range(
                maxConcurrent,
                1,
                null,
                'maxConcurrent',
              ),
        _inner = inner,
        _observers = List.unmodifiable(observers),
        _overrideGenerateAcquisitionId = generateAcquisitionId,
        _clock = clock ?? DateTime.now,
        _onDiagnostic = onDiagnostic ?? defaultHttpDiagnosticHandler,
        _semaphore = _Semaphore(maxCount: maxConcurrent);

  final SoliplexHttpClient _inner;
  final List<ConcurrencyObserver> _observers;
  final String Function()? _overrideGenerateAcquisitionId;
  final DateTime Function() _clock;
  final _Semaphore _semaphore;
  final HttpDiagnosticHandler _onDiagnostic;

  /// Monotonic counter that never resets — it tie-breaks IDs within a
  /// single millisecond. Resetting would risk collisions when a new
  /// epoch's counter coincides with a prior timestamp, and an `int`
  /// takes fixed memory regardless of magnitude.
  int _counter = 0;

  /// Maximum in-flight requests.
  final int maxConcurrent;

  String _generateAcquisitionId() =>
      _overrideGenerateAcquisitionId?.call() ??
      'acq-${_clock().millisecondsSinceEpoch}-${_counter++}';

  /// Performs a one-shot HTTP request, respecting the concurrency cap.
  ///
  /// [SoliplexHttpClient.request] has no `CancelToken`, so queued
  /// non-stream requests cannot be cancelled at this layer — they wait
  /// for their slot, dispatch, and can only be cancelled by a timeout
  /// on the inner client. Note that the timeout governs only the
  /// post-acquisition request, not queue-wait time.
  @override
  Future<HttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    final acquisitionId = _generateAcquisitionId();
    final enqueuedAt = _clock();
    final depthAtEnqueue = _semaphore.inUseCount + _semaphore.waitingCount;

    final slot = await _semaphore.acquire();

    try {
      final acquiredAt = _clock();
      _emitConcurrencyWait(
        acquisitionId: acquisitionId,
        uri: uri,
        timestamp: acquiredAt,
        waitDuration: slot.outcome == _AcquireOutcome.queued
            ? _nonNegative(acquiredAt.difference(enqueuedAt))
            : Duration.zero,
        queueDepthAtEnqueue: depthAtEnqueue,
      );

      return await _inner.request(
        method,
        uri,
        headers: headers,
        body: body,
        timeout: timeout,
      );
    } finally {
      slot.release();
    }
  }

  /// Acquires a semaphore slot and delegates to the inner client. The
  /// returned body stream is wrapped so the slot is released when the
  /// body completes, errors, or is cancelled.
  ///
  /// **Precondition:** callers MUST listen to the returned
  /// [StreamedHttpResponse.body]. An unlistened body holds the
  /// semaphore slot indefinitely, starving other requests and
  /// eventually exhausting the pool. A debug-only detector logs after
  /// 10 seconds to catch this during development; release builds do
  /// not detect the leak.
  @override
  Future<StreamedHttpResponse> requestStream(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    CancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();

    final acquisitionId = _generateAcquisitionId();
    final enqueuedAt = _clock();
    final depthAtEnqueue = _semaphore.inUseCount + _semaphore.waitingCount;

    final slot = await _semaphore.acquire(cancelToken: cancelToken);

    StreamedHttpResponse response;
    try {
      cancelToken?.throwIfCancelled();

      final acquiredAt = _clock();
      _emitConcurrencyWait(
        acquisitionId: acquisitionId,
        uri: uri,
        timestamp: acquiredAt,
        waitDuration: slot.outcome == _AcquireOutcome.queued
            ? _nonNegative(acquiredAt.difference(enqueuedAt))
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
      slot.release();
      rethrow;
    }

    return StreamedHttpResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      body: _wrapBodyWithRelease(response.body, uri, slot),
    );
  }

  /// Wraps a body stream so [slot] is released when the stream
  /// completes, errors, or is cancelled. [_SlotHandle.release] is
  /// idempotent, so multiple callback paths (onDone + onCancel,
  /// onListen-catch + onCancel) are safe.
  ///
  /// `sync: true` avoids a per-chunk microtask hop on high-rate byte
  /// streams (e.g., SSE). Backpressure is propagated by the explicit
  /// `onPause`/`onResume` forwarding below, not by the sync mode.
  Stream<List<int>> _wrapBodyWithRelease(
    Stream<List<int>> source,
    Uri uri,
    _SlotHandle slot,
  ) {
    late StreamController<List<int>> controller;
    StreamSubscription<List<int>>? subscription;
    Timer? leakDetector;

    controller = StreamController<List<int>>(
      sync: true,
      onListen: () {
        assert(
          () {
            leakDetector?.cancel();
            return true;
          }(),
          'cancel leak detector on listen',
        );
        try {
          subscription = source.listen(
            controller.add,
            onError: (Object error, StackTrace stackTrace) {
              slot.release();
              controller.addError(error, stackTrace);
            },
            onDone: () {
              slot.release();
              controller.close();
            },
          );
        } on Object catch (error, stackTrace) {
          // source.listen can throw synchronously (e.g. StateError on
          // double-listen). Without this catch, no onDone/onError ever
          // fires and the slot leaks permanently.
          slot.release();
          controller
            ..addError(error, stackTrace)
            ..close();
        }
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () {
        assert(
          () {
            leakDetector?.cancel();
            return true;
          }(),
          'cancel leak detector on body cancel',
        );
        slot.release();
        return subscription?.cancel();
      },
    );

    assert(
      () {
        leakDetector = Timer(const Duration(seconds: 10), () {
          if (!controller.hasListener) {
            _onDiagnostic(
              StateError(
                'Concurrency slot held by unlistened response body for >10s. '
                'Callers must listen to StreamedHttpResponse.body.',
              ),
              StackTrace.current,
              message: 'Unlistened body stream leak (URI: '
                  '${HttpRedactor.redactUri(uri)})',
            );
          }
        });
        return true;
      }(),
      'install debug-only unlistened-body leak detector',
    );

    return controller.stream;
  }

  @override
  void close() {
    _semaphore.closeAndDrain();
    _inner.close();
  }

  void _emitConcurrencyWait({
    required String acquisitionId,
    required Uri uri,
    required DateTime timestamp,
    required Duration waitDuration,
    required int queueDepthAtEnqueue,
  }) {
    if (_observers.isEmpty) return;

    final redactedUri = HttpRedactor.redactUri(uri);
    final ConcurrencyWaitEvent event;
    try {
      event = ConcurrencyWaitEvent(
        acquisitionId: acquisitionId,
        timestamp: timestamp,
        uri: redactedUri,
        waitDuration: waitDuration,
        queueDepthAtEnqueue: queueDepthAtEnqueue,
        slotsInUseAfterAcquire: _semaphore.inUseCount,
      );
    } on Object catch (error, stackTrace) {
      // Construction invariant violated (debug assert fired, or a
      // future runtime check). Skip this event rather than crash the
      // in-flight request.
      _onDiagnostic(
        error,
        stackTrace,
        message: 'ConcurrencyWaitEvent construction failed',
      );
      return;
    }

    for (final observer in _observers) {
      try {
        observer.onConcurrencyWait(event);
      } on Object catch (error, stackTrace) {
        _onDiagnostic(
          error,
          stackTrace,
          message: 'ConcurrencyObserver ${observer.runtimeType} threw',
        );
      }
    }
  }

  /// Clamps negative durations from clock skew (e.g., NTP adjustments)
  /// to [Duration.zero]. Logs the skew so it is visible in diagnostics.
  Duration _nonNegative(Duration duration) {
    if (!duration.isNegative) return duration;
    _onDiagnostic(
      StateError('Negative waitDuration from clock skew: $duration'),
      StackTrace.current,
      message: 'Clock went backward during request; clamping waitDuration',
    );
    return Duration.zero;
  }
}

/// Outcome of a semaphore acquisition — whether the caller was queued
/// or acquired a permit immediately.
enum _AcquireOutcome { immediate, queued }

/// Represents ownership of a single semaphore permit. [release] is
/// idempotent: calling it more than once is a no-op. Ownership lives
/// only within the file; handles are never exposed to library callers.
class _SlotHandle {
  _SlotHandle._(this._semaphore, this.outcome);

  final _Semaphore _semaphore;
  final _AcquireOutcome outcome;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _semaphore._onSlotReleased();
  }
}

/// Cancel-aware FIFO semaphore.
///
/// [acquire] returns a [_SlotHandle] immediately if a permit is
/// available; otherwise the caller is queued. If a [CancelToken] is
/// passed and fires while the caller is queued, the completer is
/// removed from the queue and completed with a [CancelledException] —
/// no permit is acquired.
///
/// After [closeAndDrain], all queued waiters and future acquires error
/// with [CancelledException].
class _Semaphore {
  _Semaphore({required this.maxCount}) : _available = maxCount;

  final int maxCount;
  int _available;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();
  bool _closed = false;

  int get inUseCount => maxCount - _available;

  int get waitingCount => _waiters.length;

  Future<_SlotHandle> acquire({CancelToken? cancelToken}) {
    if (_closed) {
      return Future<_SlotHandle>.error(
        const CancelledException(reason: 'HTTP client closed'),
      );
    }

    if (_available > 0) {
      _available--;
      return Future<_SlotHandle>.value(
        _SlotHandle._(this, _AcquireOutcome.immediate),
      );
    }
    cancelToken?.throwIfCancelled();

    final completer = Completer<void>();
    _waiters.add(completer);

    if (cancelToken != null) {
      // Dart's single-threaded run-to-completion guarantees no
      // interleaving between the isCompleted check and completeError.
      unawaited(
        cancelToken.whenCancelled.then((_) {
          if (!completer.isCompleted) {
            _waiters.remove(completer);
            completer.completeError(
              CancelledException(reason: cancelToken.reason),
            );
          }
        }),
      );
    }

    return completer.future
        .then((_) => _SlotHandle._(this, _AcquireOutcome.queued));
  }

  /// Hands the permit to the next queued waiter, or returns it to
  /// the pool.
  void _onSlotReleased() {
    // Invariant: every completer in [_waiters] is uncompleted (the
    // cancel handler in [acquire] removes completed completers from the
    // queue before completing them). So we can hand the permit to the
    // head without a skip-loop.
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
      return;
    }
    _available++;
  }

  /// Errors out all queued waiters and refuses future acquires.
  /// Idempotent. In-flight slots are left alone — they release normally
  /// when their requests complete.
  void closeAndDrain() {
    if (_closed) return;
    _closed = true;
    while (_waiters.isNotEmpty) {
      _waiters.removeFirst().completeError(
            const CancelledException(
              reason: 'HTTP client closed before slot acquired',
            ),
          );
    }
  }
}
