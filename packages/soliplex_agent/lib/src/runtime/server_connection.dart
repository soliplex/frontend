import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _apiLogger = LogManager.instance.getLogger('soliplex_client.api');

/// Bundle of API clients for a single backend server.
///
/// Use [ServerConnection.create] to build from a server URL and HTTP client.
/// The raw constructor accepts pre-built clients for test injection.
///
/// Call [close] when the connection is no longer needed.
class ServerConnection {
  /// Creates a connection from pre-built clients.
  ///
  /// Prefer [ServerConnection.create] for production wiring.
  const ServerConnection({
    required this.serverId,
    required this.api,
    required this.agUiStreamClient,
    Future<void> Function()? onClose,
  }) : _onClose = onClose;

  /// Creates a connection from a server URL and HTTP client.
  ///
  /// A single [httpClient] is shared for both REST and SSE — AG-UI
  /// streams are request-scoped, so no isolation is needed.
  ///
  /// [serverUrl] must be the root URL (e.g. `http://localhost:8000`).
  /// The `/api/v1` prefix is added automatically — do not include it.
  factory ServerConnection.create({
    required String serverId,
    required String serverUrl,
    required SoliplexHttpClient httpClient,
    Future<void> Function()? onClose,
  }) {
    assert(
      !serverUrl.endsWith('/api/v1') && !serverUrl.endsWith('/api/v1/'),
      'serverUrl should be the root URL without /api/v1 suffix. '
      'Got: $serverUrl',
    );
    final baseUrl = '$serverUrl/api/v1';
    final transport = HttpTransport(client: httpClient);
    final urlBuilder = UrlBuilder(baseUrl);
    return ServerConnection(
      serverId: serverId,
      api: SoliplexApi(
        transport: transport,
        urlBuilder: urlBuilder,
        onWarning: _apiLogger.warning,
      ),
      agUiStreamClient: AgUiStreamClient(
        httpTransport: transport,
        urlBuilder: urlBuilder,
      ),
      onClose: onClose,
    );
  }

  /// Unique identifier for this server (e.g. `'prod'`,
  /// `'staging.soliplex.io'`).
  final String serverId;

  /// REST API client for this server.
  final SoliplexApi api;

  /// AG-UI streaming client for this server.
  final AgUiStreamClient agUiStreamClient;

  final Future<void> Function()? _onClose;

  /// Closes the API client (and its shared transport), then invokes any
  /// injected teardown.
  Future<void> close() async {
    api.close();
    await _onClose?.call();
  }

  @override
  String toString() => 'ServerConnection(serverId: $serverId)';
}
