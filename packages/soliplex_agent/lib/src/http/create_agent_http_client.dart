import 'package:soliplex_client/soliplex_client.dart';

/// Creates an HTTP client for agent connections with observability,
/// concurrency limiting, and authentication.
///
/// [tokenRefresher] must use a SEPARATE HTTP client (not this one) to
/// avoid deadlock — a refresh triggered while the pool is exhausted
/// would try to acquire a slot from the pool it's unblocking.
///
/// [maxConcurrent] caps simultaneous in-flight requests. The default of
/// 6 aligns with the per-host HTTP/1.1 connection cap that browsers,
/// `URLSession`, and Dart's `HttpClient` all impose, which makes this
/// layer's queue the authoritative one — queue-wait events surface in
/// observer diagnostics instead of being absorbed silently by the
/// platform client. 6 sits under the backend's per-client 10-connection
/// cap with headroom. Raise it when moving to an HTTP/2 backend.
///
/// See `package:soliplex_client/CLAUDE.md` for the decorator stack
/// rationale.
SoliplexHttpClient createAgentHttpClient({
  SoliplexHttpClient? innerClient,
  List<HttpObserver>? observers,
  String? Function()? getToken,
  TokenRefresher? tokenRefresher,
  int maxConcurrent = 6,
  HttpDiagnosticHandler? onDiagnostic,
}) {
  assert(
    tokenRefresher == null || getToken != null,
    'tokenRefresher requires getToken to inject refreshed tokens',
  );

  var client = innerClient ?? DartHttpClient();

  if (observers != null && observers.isNotEmpty) {
    client = ObservableHttpClient(
      client: client,
      observers: observers,
      onDiagnostic: onDiagnostic,
    );
  }

  if (getToken != null) {
    client = AuthenticatedHttpClient(client, getToken);
  }

  if (tokenRefresher != null) {
    client = RefreshingHttpClient(inner: client, refresher: tokenRefresher);
  }

  // Observers that implement both [HttpObserver] and [ConcurrencyObserver]
  // receive both kinds of events. Observers implementing only one are
  // silently filtered from the other channel.
  return ConcurrencyLimitingHttpClient(
    inner: client,
    maxConcurrent: maxConcurrent,
    observers: observers?.whereType<ConcurrencyObserver>().toList() ?? const [],
    onDiagnostic: onDiagnostic,
  );
}
