import 'package:soliplex_client/soliplex_client.dart';

/// Creates an HTTP client for agent connections with observability,
/// concurrency limiting, and authentication.
///
/// [tokenRefresher] must use a SEPARATE HTTP client (not this one) to
/// avoid deadlock — a refresh triggered while the pool is exhausted
/// would try to acquire a slot from the pool it's unblocking.
///
/// See `package:soliplex_client/CLAUDE.md` for the decorator stack
/// rationale.
SoliplexHttpClient createAgentHttpClient({
  SoliplexHttpClient? innerClient,
  List<HttpObserver>? observers,
  String? Function()? getToken,
  TokenRefresher? tokenRefresher,
  int maxConcurrent = 10,
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

  return ConcurrencyLimitingHttpClient(
    inner: client,
    maxConcurrent: maxConcurrent,
    observers: observers?.whereType<ConcurrencyObserver>().toList() ?? const [],
    onDiagnostic: onDiagnostic,
  );
}
