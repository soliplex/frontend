import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';

import 'fakes.dart';

ServerEntry createTestServerEntry({
  FakeSoliplexApi? api,
  String serverId = 'http://test-server:8000',
  String alias = 'test-server-8000',
  bool requiresAuth = false,
  AuthSession? auth,
  FakeHttpClient? httpClient,
}) {
  final fakeApi = api ?? FakeSoliplexApi();
  return ServerEntry(
    serverId: serverId,
    alias: alias,
    serverUrl: Uri.parse(serverId),
    auth: auth ?? AuthSession(refreshService: FakeTokenRefreshService()),
    httpClient: httpClient ?? FakeHttpClient(),
    connection: ServerConnection(
      serverId: serverId,
      api: fakeApi,
      agUiStreamClient: FakeAgUiStreamClient(),
    ),
    requiresAuth: requiresAuth,
  );
}

/// An [AuthSession] already in its [ActiveSession] state, for tests that need
/// to exercise authenticated-only paths (e.g. the rail's account fetch).
AuthSession authInActiveSession() {
  final auth = AuthSession(refreshService: FakeTokenRefreshService());
  auth.login(
    provider: const OidcProvider(
      discoveryUrl: 'https://auth.example.com/.well-known/openid-configuration',
      clientId: 'test-client',
    ),
    tokens: AuthTokens(
      accessToken: 'access',
      refreshToken: 'refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    ),
  );
  return auth;
}
