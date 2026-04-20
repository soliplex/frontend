import 'dart:developer' as dev;

import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;

import 'auth_flow.dart';

/// Creates the native platform implementation of [AuthFlow].
///
/// [redirectScheme] is the OAuth redirect URI scheme (e.g., 'ai.soliplex.client').
/// [appAuth] enables testing with a mock FlutterAppAuth.
AuthFlow createAuthFlow({
  required String redirectScheme,
  FlutterAppAuth? appAuth,
}) => NativeAuthFlow(
  appAuth: appAuth ?? const FlutterAppAuth(),
  redirectScheme: redirectScheme,
);

/// Native OIDC authentication using flutter_appauth.
///
/// Opens the system browser for IdP login. Handles PKCE automatically.
class NativeAuthFlow implements AuthFlow {
  NativeAuthFlow({
    required FlutterAppAuth appAuth,
    required String redirectScheme,
  }) : _appAuth = appAuth,
       _redirectUri = '$redirectScheme://callback';

  final FlutterAppAuth _appAuth;
  final String _redirectUri;

  @override
  Future<AuthResult> authenticate(
    AuthProviderConfig provider, {
    Uri? backendUrl,
  }) async {
    final discoveryUrl =
        '${provider.serverUrl}/.well-known/openid-configuration';
    try {
      final result = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          provider.clientId,
          _redirectUri,
          discoveryUrl: discoveryUrl,
          scopes: provider.scope.split(' '),
          externalUserAgent:
              ExternalUserAgent.ephemeralAsWebAuthenticationSession,
        ),
      );

      final accessToken = result.accessToken;
      if (accessToken == null) {
        throw const AuthException('IdP returned success but no access token');
      }

      return AuthResult(
        accessToken: accessToken,
        refreshToken: result.refreshToken,
        idToken: result.idToken,
        expiresAt: result.accessTokenExpirationDateTime,
      );
    } on AuthException {
      rethrow;
    } on Exception catch (e, st) {
      dev.log('NativeAuthFlow.authenticate', error: e, stackTrace: st);
      throw AuthException(
        'Authentication failed (${e.runtimeType}). Please try again.',
      );
    }
  }

  @override
  Future<void> endSession({
    required String discoveryUrl,
    required String? endSessionEndpoint,
    required String idToken,
    required String clientId,
  }) async {
    try {
      await _appAuth.endSession(
        EndSessionRequest(
          idTokenHint: idToken,
          discoveryUrl: discoveryUrl,
          postLogoutRedirectUrl: _redirectUri,
        ),
      );
    } on Exception catch (e, st) {
      // IdP session cleanup is best-effort; local logout already handled.
      dev.log('NativeAuthFlow.endSession', error: e, stackTrace: st);
    }
  }
}
