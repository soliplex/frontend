import 'package:soliplex_agent/soliplex_agent.dart';

import 'auth_session.dart';

/// Canonical server identity: scheme + host + port (default ports omitted).
///
/// Used as storage keys and registry keys. Do not change without migration.
String serverIdFromUrl(Uri url) => url.origin;

/// Path-safe slug derived from a server URL: host dots become hyphens,
/// non-default port appended.
String aliasFromUrl(Uri url) {
  final host = url.host.replaceAll('.', '-');
  return url.hasPort ? '$host-${url.port}' : host;
}

/// Formats a server URL for display: always includes scheme, omits unspecified port.
String formatServerUrl(Uri url) {
  final port = url.hasPort ? ':${url.port}' : '';
  return '${url.scheme}://${url.host}$port';
}

/// Groups everything that lives and dies with a server.
class ServerEntry {
  const ServerEntry({
    required this.serverId,
    required this.alias,
    required this.serverUrl,
    required this.auth,
    required this.httpClient,
    required this.connection,
    this.requiresAuth = true,
    this.name,
    this.description,
  });

  final String serverId;
  final String alias;
  final Uri serverUrl;
  final AuthSession auth;
  final SoliplexHttpClient httpClient;
  final ServerConnection connection;
  final bool requiresAuth;

  /// Human-readable server name (e.g., "Demo Server"), or `null` when the
  /// server provides none. Display sites fall back to [formatServerUrl].
  final String? name;

  /// Brief server description, or `null` when the server provides none.
  final String? description;

  /// Preferred display label: the human-readable [name] when available,
  /// otherwise the formatted server address.
  String get displayName => name ?? formatServerUrl(serverUrl);

  bool get isConnected => !requiresAuth || auth.isAuthenticated;
}
