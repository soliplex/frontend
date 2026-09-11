import 'package:soliplex_agent/soliplex_agent.dart';

import 'admin_status.dart';
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

/// A server label with any leading `http(s)://` scheme removed, for compact
/// header/title display where a leading glyph or surrounding context already
/// implies a URL. A human-readable server name (which carries no scheme) is
/// returned unchanged.
String stripUrlScheme(String label) =>
    label.replaceFirst(RegExp('^https?://'), '');

/// Groups everything that lives and dies with a server.
class ServerEntry {
  const ServerEntry({
    required this.serverId,
    required this.alias,
    required this.serverUrl,
    required this.auth,
    required this.httpClient,
    required this.connection,
    required this.adminStatus,
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

  /// Asks whether the signed-in user administers this server, on demand, and
  /// keeps a verdict the installation delivered. See [AdminStatus] for which
  /// answers are kept and what clears them.
  final AdminStatus adminStatus;

  final bool requiresAuth;

  /// Human-readable server name (e.g., "Demo Server"), or `null` when the
  /// server provides none. Display sites fall back to [formatServerUrl].
  final String? name;

  /// Brief server description, or `null` when the server provides none.
  final String? description;

  /// Preferred display label: the human-readable [name] when available,
  /// otherwise the formatted server address.
  String get displayName => name ?? formatServerUrl(serverUrl);

  /// The address without its scheme, port kept. Adding a server passes a
  /// blocking "this connection is not encrypted" screen when the scheme is
  /// `http`, so the list does not repeat that warning on every row.
  String get bareAddress => stripUrlScheme(formatServerUrl(serverUrl));

  /// What the server lists show: the human [name] when set, otherwise
  /// [bareAddress].
  ///
  /// Composed from [name] and [serverUrl] rather than stripping [displayName],
  /// so the regex only ever sees a URL: a server named `https://prod (legacy)`
  /// keeps its name intact.
  String get listLabel => name ?? bareAddress;

  bool get isConnected => !requiresAuth || auth.isAuthenticated;
}

/// Auth servers first (signed in, then signed out), no-auth last; alphabetical
/// by [ServerEntry.listLabel] within a rank, ignoring case.
///
/// Sorting the label rather than the address keeps the order matching what the
/// reader sees: an address sort compares `http:` against `https:` before either
/// host, so `http://zebra` would precede `https://apple`.
///
/// Auth servers lead because they are the deployments people work in; a no-auth
/// server is typically local or for testing. That is why a signed-out auth
/// server outranks a no-auth one despite needing more taps to use — the rank
/// asks which server matters, not which is closest to hand.
List<ServerEntry> serversInDisplayOrder(Iterable<ServerEntry> servers) {
  int rank(ServerEntry entry) {
    if (!entry.requiresAuth) return 2;
    return entry.auth.isAuthenticated ? 0 : 1;
  }

  return servers.toList()
    ..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      return a.listLabel.toLowerCase().compareTo(b.listLabel.toLowerCase());
    });
}
