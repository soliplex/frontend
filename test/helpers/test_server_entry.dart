import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';

import 'fakes.dart';

ServerEntry createTestServerEntry({
  FakeSoliplexApi? api,
  String serverId = 'http://test-server:8000',
  String alias = 'test-server-8000',
}) {
  final fakeApi = api ?? FakeSoliplexApi();
  return ServerEntry(
    serverId: serverId,
    alias: alias,
    serverUrl: Uri.parse(serverId),
    auth: AuthSession(refreshService: FakeTokenRefreshService()),
    httpClient: FakeHttpClient(),
    connection: ServerConnection(
      serverId: serverId,
      api: fakeApi,
      agUiStreamClient: FakeAgUiStreamClient(),
    ),
    requiresAuth: false,
  );
}
