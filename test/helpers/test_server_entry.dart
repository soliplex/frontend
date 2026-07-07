import 'dart:convert';

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
  String? name,
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
    name: name,
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

/// The `iss#sub` identity embedded in the access token of [authWithIdentity],
/// i.e. the value its `currentUserId` resolves to — use it as the `userId` when
/// asserting against user-scoped device-local storage.
const testUserIdentity = 'https://idp.test#test-user';

/// The identity (`iss#sub`) that [authWithIdentity] embeds for a given [sub],
/// under the default `iss`. Use as the `userId` when asserting against
/// user-scoped storage.
String testIdentityFor(String sub) => 'https://idp.test#$sub';

/// An [AuthSession] in [ActiveSession] whose access token is a decodable JWT
/// carrying `iss#`[sub], so `currentUserId` resolves to a stable user and
/// user-scoped stores (thread markers, anchors, drafts) actually persist. Pass a
/// distinct [sub] to model a different user on another server.
AuthSession authWithIdentity({String sub = 'test-user'}) {
  final auth = AuthSession(refreshService: FakeTokenRefreshService());
  auth.login(
    provider: const OidcProvider(
      discoveryUrl: 'https://auth.example.com/.well-known/openid-configuration',
      clientId: 'test-client',
    ),
    tokens: AuthTokens(
      accessToken: testAccessToken(sub: sub),
      refreshToken: 'refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    ),
  );
  return auth;
}

/// A decodable JWT access token embedding `https://idp.test#`[sub], for logging
/// a [ServerManager] entry into a specific identity (`entry.auth.login`) so its
/// `currentUserId` resolves to [testIdentityFor]`(sub)`.
String testAccessToken({String sub = 'test-user'}) =>
    _jwt('https://idp.test', sub);

/// Builds a JWT-shaped `header.payload.signature` string embedding [iss]/[sub].
String _jwt(String iss, String sub) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${seg({'alg': 'RS256'})}.${seg({'iss': iss, 'sub': sub})}.sig';
}
