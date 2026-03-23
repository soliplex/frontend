import 'package:soliplex_agent/soliplex_agent.dart';

import 'auth_session.dart';

/// Canonical server identity: scheme + host + port (default ports omitted).
///
/// Used as storage keys and registry keys. Do not change without migration.
String serverIdFromUrl(Uri url) => url.origin;

/// Formats a server URL for display: always includes scheme, omits unspecified port.
String formatServerUrl(Uri url) {
  final port = url.hasPort ? ':${url.port}' : '';
  return '${url.scheme}://${url.host}$port';
}

/// Groups everything that lives and dies with a server.
class ServerEntry {
  const ServerEntry({
    required this.serverId,
    required this.serverUrl,
    required this.auth,
    required this.httpClient,
    required this.connection,
    this.requiresAuth = true,
  });

  final String serverId;
  final Uri serverUrl;
  final AuthSession auth;
  final SoliplexHttpClient httpClient;
  final ServerConnection connection;
  final bool requiresAuth;

  bool get isConnected => !requiresAuth || auth.isAuthenticated;
}
