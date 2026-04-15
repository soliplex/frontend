import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:soliplex_client/src/errors/exceptions.dart';
import 'package:soliplex_client/src/http/http_response.dart';
import 'package:soliplex_client/src/http/soliplex_http_client.dart';
import 'package:soliplex_client/src/utils/cancel_token.dart';

/// Set of HTTP status codes that are safe to retry.
const _retryableStatusCodes = {429, 502, 503, 504};

/// HTTP client decorator that retries transient failures with exponential
/// backoff and limits concurrency.
///
/// Retries on:
/// - HTTP 429 (rate limited), 502, 503, 504
/// - [NetworkException] (connection failures, timeouts)
///
/// Does **not** retry:
/// - 401/403 (auth — handled by `RefreshingHttpClient`)
/// - 400, 404, 422, etc. (client errors — not transient)
/// - [CancelledException] (user intent)
///
/// For 429 responses, the `Retry-After` header value is used as a floor
/// for the backoff delay when present.
///
/// ## Concurrency
///
/// At most [maxConcurrent] requests are in-flight simultaneously. Excess
/// requests queue in FIFO order and proceed as earlier requests complete.
/// This provides natural back-pressure and reduces the likelihood of
/// triggering server-side rate limits.
///
/// ## Streaming requests
///
/// For [requestStream], only **connection-time** errors are retried (status
/// code on the initial HTTP response, or a [NetworkException] during
/// connect). Mid-stream errors after a successful connection cannot be
/// retried at this layer — the body stream has already been partially
/// consumed.
///
/// ## Decorator order
///
/// Place inside `AuthenticatedHttpClient` so each retry attempt gets a
/// fresh token, and outside `ObservableHttpClient` so each attempt is
/// individually observable:
///
/// ```text
/// Refreshing -> Authenticated -> Retrying -> Observable -> Platform
/// ```
class RetryingHttpClient implements SoliplexHttpClient {
  /// Creates a retrying HTTP client.
  ///
  /// - [inner]: The wrapped HTTP client.
  /// - [maxRetries]: Maximum number of retry attempts (default 3).
  /// - [maxBackoff]: Ceiling for backoff delay (default 30 seconds).
  /// - [maxConcurrent]: Maximum in-flight requests (default 6).
  /// - [random]: Optional [Random] for jitter (injectable for tests).
  RetryingHttpClient({
    required SoliplexHttpClient inner,
    this.maxRetries = 3,
    this.maxBackoff = const Duration(seconds: 30),
    this.maxConcurrent = 6,
    Random? random,
  })  : _inner = inner,
        _random = random ?? Random(),
        _semaphore = _Semaphore(maxConcurrent);

  final SoliplexHttpClient _inner;

  /// Maximum number of retry attempts before giving up.
  final int maxRetries;

  /// Upper bound for backoff delay.
  final Duration maxBackoff;

  /// Maximum number of concurrent in-flight requests.
  final int maxConcurrent;

  final Random _random;
  final _Semaphore _semaphore;

  @override
  Future<HttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    await _semaphore.acquire();
    try {
      return await _requestWithRetry(
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

  Future<HttpResponse> _requestWithRetry(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      if (attempt > 0) {
        await _backoff(attempt, lastError);
      }

      try {
        final response = await _inner.request(
          method,
          uri,
          headers: headers,
          body: body,
          timeout: timeout,
        );

        if (_retryableStatusCodes.contains(response.statusCode) &&
            attempt < maxRetries) {
          // Stash the response info for backoff calculation on next
          // iteration. Wrap in a lightweight ApiException so _backoff
          // can extract retryAfter if present.
          lastError = ApiException(
            message: 'HTTP ${response.statusCode}',
            statusCode: response.statusCode,
            retryAfter: _parseRetryAfter(response.headers),
          );
          lastStackTrace = StackTrace.current;
          continue;
        }

        return response;
      } on NetworkException catch (e, st) {
        lastError = e;
        lastStackTrace = st;
        if (attempt >= maxRetries) rethrow;
      } on CancelledException {
        rethrow;
      }
    }

    // Should not be reached — the last iteration either returns or
    // rethrows. Safety net in case of logic errors.
    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  @override
  Future<StreamedHttpResponse> requestStream(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    CancelToken? cancelToken,
  }) async {
    await _semaphore.acquire();
    try {
      return await _requestStreamWithRetry(
        method,
        uri,
        headers: headers,
        body: body,
        cancelToken: cancelToken,
      );
    } on Object {
      // Only release on error — successful streams release when the
      // body completes or is cancelled (see _wrapBodyWithRelease).
      _semaphore.release();
      rethrow;
    }
  }

  Future<StreamedHttpResponse> _requestStreamWithRetry(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    CancelToken? cancelToken,
  }) async {
    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      if (attempt > 0) {
        cancelToken?.throwIfCancelled();
        await _backoff(attempt, lastError);
        cancelToken?.throwIfCancelled();
      }

      try {
        final response = await _inner.requestStream(
          method,
          uri,
          headers: headers,
          body: body,
          cancelToken: cancelToken,
        );

        if (_retryableStatusCodes.contains(response.statusCode) &&
            attempt < maxRetries) {
          // Drain the body to release the socket before retrying.
          unawaited(response.body.listen((_) {}).cancel());
          lastError = ApiException(
            message: 'HTTP ${response.statusCode}',
            statusCode: response.statusCode,
            retryAfter: _parseRetryAfter(response.headers),
          );
          lastStackTrace = StackTrace.current;
          continue;
        }

        // Wrap the body stream so the semaphore is released when the
        // stream finishes, errors, or is cancelled.
        return StreamedHttpResponse(
          statusCode: response.statusCode,
          headers: response.headers,
          reasonPhrase: response.reasonPhrase,
          body: _wrapBodyWithRelease(response.body),
        );
      } on NetworkException catch (e, st) {
        lastError = e;
        lastStackTrace = st;
        if (attempt >= maxRetries) rethrow;
      } on CancelledException {
        rethrow;
      }
    }

    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  /// Wraps a stream body so the semaphore slot is released when the
  /// stream completes, errors, or is cancelled.
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

  /// Sleeps for an exponential backoff duration with jitter.
  ///
  /// Backoff formula: `min(2^(attempt-1), maxBackoff) + jitter`.
  /// For 429 responses with a `Retry-After` header, the server-suggested
  /// delay is used as a floor.
  Future<void> _backoff(int attempt, Object? lastError) async {
    // Base: 1s, 2s, 4s, 8s, ...
    final baseMs =
        min(pow(2, attempt - 1).toInt() * 1000, maxBackoff.inMilliseconds);
    // Jitter: 0–1000ms
    final jitterMs = _random.nextInt(1000);
    var delayMs = baseMs + jitterMs;

    // Floor with Retry-After when available.
    if (lastError is ApiException && lastError.retryAfter != null) {
      delayMs = max(delayMs, lastError.retryAfter!.inMilliseconds);
    }

    // Clamp to maxBackoff (Retry-After can exceed it, but we cap).
    delayMs = min(delayMs, maxBackoff.inMilliseconds);

    await Future<void>.delayed(Duration(milliseconds: delayMs));
  }

  /// Parses the `Retry-After` header (delay-seconds form only).
  static Duration? _parseRetryAfter(Map<String, String> headers) {
    final value = headers['retry-after'];
    if (value == null || value.isEmpty) return null;
    final seconds = int.tryParse(value);
    if (seconds == null || seconds <= 0) return null;
    return Duration(seconds: seconds);
  }
}

/// FIFO semaphore that limits concurrency to [maxCount] permits.
///
/// [acquire] returns immediately if a permit is available, otherwise the
/// caller is queued and the returned future completes when a permit is
/// released.
class _Semaphore {
  _Semaphore(this.maxCount) : _available = maxCount;

  /// Maximum number of concurrent permits.
  final int maxCount;

  int _available;
  final _waiters = Queue<Completer<void>>();

  /// Acquires a permit. Returns immediately if one is available,
  /// otherwise waits in FIFO order.
  Future<void> acquire() {
    if (_available > 0) {
      _available--;
      return Future<void>.value();
    }
    final completer = Completer<void>.sync();
    _waiters.add(completer);
    return completer.future;
  }

  /// Releases a permit and unblocks the next waiter, if any.
  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else {
      _available++;
    }
  }
}
