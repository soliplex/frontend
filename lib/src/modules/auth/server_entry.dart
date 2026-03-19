import 'package:soliplex_agent/soliplex_agent.dart';

import 'auth_session.dart';

/// Groups everything that lives and dies with a server.
class ServerEntry {
  const ServerEntry({
    required this.serverId,
    required this.serverUrl,
    required this.auth,
    required this.httpClient,
    required this.connection,
  });

  final String serverId;
  final Uri serverUrl;
  final AuthSession auth;
  final SoliplexHttpClient httpClient;
  final ServerConnection connection;
}
