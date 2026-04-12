import 'package:meta/meta.dart';
import 'package:soliplex_client/soliplex_client.dart';

/// Bundles a [SoliplexApi] and [AgUiStreamClient] for a single server.
///
/// Lightweight adapter so the plugin does not depend on `soliplex_agent`'s
/// `ServerConnection`. Callers construct this from whatever wiring they have.
@immutable
class SoliplexConnection {
  /// Creates a connection from pre-built clients.
  const SoliplexConnection({
    required this.api,
    required this.streamClient,
  });

  /// REST API client for CRUD operations.
  final SoliplexApi api;

  /// AG-UI streaming client for SSE run execution.
  final AgUiStreamClient streamClient;
}
