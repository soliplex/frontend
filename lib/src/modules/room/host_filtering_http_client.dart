import 'package:soliplex_client/soliplex_client.dart';

import 'access_policy.dart';

/// HTTP client decorator that enforces [AccessPolicy] host restrictions.
///
/// Blocks connections to denied hosts **before** a TCP connection opens —
/// the check runs synchronously in `request()` and `requestStream()` before
/// delegating to the inner client.
///
/// [policy] is mutable so it can be tightened when a room session delivers
/// its server-side configuration without rebuilding the client stack.
///
/// Wired as the outermost decorator (above `ConcurrencyLimitingHttpClient`)
/// so denied requests never consume a concurrency slot.
class HostFilteringHttpClient implements SoliplexHttpClient {
  /// Creates a [HostFilteringHttpClient] wrapping [inner].
  HostFilteringHttpClient({
    required SoliplexHttpClient inner,
    AccessPolicy policy = AccessPolicy.permissive,
  })  : _inner = inner,
        _policy = policy;

  final SoliplexHttpClient _inner;
  AccessPolicy _policy;

  /// Updates the active policy (e.g. when room server config arrives).
  // ignore: avoid_setters_without_getters
  set policy(AccessPolicy value) => _policy = value;

  @override
  Future<HttpResponse> request(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) {
    _assertHostAllowed(uri.host);
    return _inner.request(method, uri, headers: headers, body: body,
        timeout: timeout);
  }

  @override
  Future<StreamedHttpResponse> requestStream(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    CancelToken? cancelToken,
  }) {
    _assertHostAllowed(uri.host);
    return _inner.requestStream(method, uri, headers: headers, body: body,
        cancelToken: cancelToken);
  }

  @override
  void close() => _inner.close();

  void _assertHostAllowed(String host) {
    if (!_policy.hostAllowed(host)) {
      throw PolicyException(
        message: 'Connection to "$host" is not permitted in this session',
      );
    }
  }
}
