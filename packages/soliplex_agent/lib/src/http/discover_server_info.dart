import 'package:soliplex_client/soliplex_client.dart';

/// Fetches a Soliplex server's human-readable identity.
///
/// Wraps the underlying [fetchServerInfo] call so consumers don't need to
/// create an [HttpTransport] directly.
///
/// [serverUrl] is the backend base URL (e.g., `https://api.example.com`).
/// [httpClient] should come from `createAgentHttpClient` — valid with or
/// without auth parameters.
///
/// Returns `null` when the server configures no name/description (the backend
/// responds 404), so callers can fall back to the raw server address.
Future<ServerInfo?> discoverServerInfo({
  required Uri serverUrl,
  required SoliplexHttpClient httpClient,
}) {
  final transport = HttpTransport(client: httpClient);
  return fetchServerInfo(transport: transport, baseUrl: serverUrl);
}
