import 'dart:async';

import 'package:soliplex_client/src/http/http_response.dart';
import 'package:soliplex_client/src/http/soliplex_http_client.dart';
import 'package:soliplex_client/src/http/token_refresher.dart';
import 'package:soliplex_client/src/utils/cancel_token.dart';

/// HTTP client decorator that handles token refresh.
///
/// Wraps an inner client to provide:
/// - Proactive refresh before requests when token is expiring soon
/// - Reactive refresh and retry on 401 responses (once only per request)
/// - Concurrent refresh deduplication via Completer
///
/// ## Concurrent Refresh Handling
///
/// When multiple requests receive 401 simultaneously, only one refresh
/// call is made. Other requests wait on the same Completer. The Completer
/// is cleared synchronously before completing to ensure subsequent requests
/// start fresh refresh attempts if needed.
///
/// Decorator order:
/// `Concurrency -> Refreshing -> Authenticated -> Observable -> Platform`
class RefreshingHttpClient implements SoliplexHttpClient {
  /// Creates a refreshing HTTP client.
  ///
  /// [inner] is the wrapped HTTP client (typically AuthenticatedHttpClient).
  /// [refresher] provides token refresh capabilities.
  RefreshingHttpClient({
    required SoliplexHttpClient inner,
    required TokenRefresher refresher,
  })  : _inner = inner,
        _refresher = refresher;

  final SoliplexHttpClient _inner;
  final TokenRefresher _refresher;

  /// Guards concurrent refresh attempts.
  Completer<bool>? _refreshInProgress;

  @override
  Future<HttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    // Proactive refresh if token is expiring soon
    await _refresher.refreshIfExpiringSoon();

    return _executeWithRetry(
      method,
      uri,
      headers: headers,
      body: body,
      timeout: timeout,
      retried: false,
    );
  }

  Future<HttpResponse> _executeWithRetry(
    String method,
    Uri uri, {
    required bool retried,
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    final response = await _inner.request(
      method,
      uri,
      headers: headers,
      body: body,
      timeout: timeout,
    );

    // On 401, attempt refresh and retry ONCE (CWE-834 prevention)
    if (response.statusCode == 401 && !retried) {
      final refreshed = await _tryRefreshOnce();
      if (refreshed) {
        return _executeWithRetry(
          method,
          uri,
          headers: headers,
          body: body,
          timeout: timeout,
          retried: true,
        );
      }
    }

    return response;
  }

  /// Attempt refresh with concurrent call deduplication.
  ///
  /// Uses a [Completer] as a semaphore: multiple concurrent 401s share a
  /// single refresh attempt by awaiting the same Completer. After refresh
  /// completes (success or failure), the Completer reference is cleared so
  /// subsequent requests trigger fresh refresh attempts.
  ///
  /// The null-clearing is critical: a [Completer] can only complete once, and
  /// afterward `.future` returns the cached result forever. Without clearing,
  /// new 401s would receive stale results instead of refreshing.
  Future<bool> _tryRefreshOnce() async {
    // Dart's single-threaded event loop guarantees no interleaving
    // between the null check and assignment below — code only yields
    // at `await` points, so this check-then-assign is atomic.
    if (_refreshInProgress != null) {
      return _refreshInProgress!.future;
    }

    final completer = Completer<bool>();
    _refreshInProgress = completer;
    try {
      final result = await _refresher.tryRefresh();
      completer.complete(result);
      _refreshInProgress = null;
      return result;
    } catch (e, stackTrace) {
      completer.completeError(e, stackTrace);
      _refreshInProgress = null;
      rethrow;
    }
  }

  @override
  Future<StreamedHttpResponse> requestStream(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    CancelToken? cancelToken,
  }) async {
    // Proactive refresh only - can't retry mid-stream on 401
    await _refresher.refreshIfExpiringSoon();

    return _inner.requestStream(
      method,
      uri,
      headers: headers,
      body: body,
      cancelToken: cancelToken,
    );
  }

  @override
  void close() => _inner.close();
}
