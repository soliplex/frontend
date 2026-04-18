import 'package:meta/meta.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart';

/// Bundles a [SoliplexApi] and [AgUiStreamClient] for a single server,
/// along with human-readable metadata for display and LLM context.
@immutable
class SoliplexConnection {
  /// Creates a connection from pre-built clients.
  const SoliplexConnection({
    required this.serverId,
    required this.alias,
    required this.serverUrl,
    required this.api,
    required this.streamClient,
  });

  /// Creates a connection from a [ServerConnection] and its display metadata.
  ///
  /// [alias] is a human-readable name (e.g. `"demo-toughserv-com"`).
  /// [serverUrl] is the origin URL string (e.g. `"https://demo.toughserv.com"`).
  factory SoliplexConnection.fromServerConnection(
    ServerConnection conn, {
    required String alias,
    required String serverUrl,
  }) {
    return SoliplexConnection(
      serverId: conn.serverId,
      alias: alias,
      serverUrl: serverUrl,
      api: conn.api,
      streamClient: conn.agUiStreamClient,
    );
  }

  /// The canonical server identifier.
  final String serverId;

  /// Human-readable name for the server (e.g. `"demo-toughserv-com"`).
  final String alias;

  /// Origin URL string (e.g. `"https://demo.toughserv.com"`).
  final String serverUrl;

  /// REST API client for CRUD operations.
  final SoliplexApi api;

  /// AG-UI streaming client for SSE run execution.
  final AgUiStreamClient streamClient;
}
