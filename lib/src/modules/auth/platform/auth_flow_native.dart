import 'package:flutter/services.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;
import 'package:soliplex_logging/soliplex_logging.dart';

import 'auth_flow.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.auth_flow_native');

/// Creates the native platform implementation of [AuthFlow].
///
/// [redirectScheme] is the OAuth redirect URI scheme (e.g., 'ai.soliplex.client').
/// [appAuth] enables testing with a mock FlutterAppAuth.
AuthFlow createAuthFlow({
  required String redirectScheme,
  FlutterAppAuth? appAuth,
}) =>
    NativeAuthFlow(
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
  })  : _appAuth = appAuth,
        _redirectUri = '$redirectScheme://callback';

  final FlutterAppAuth _appAuth;
  final String _redirectUri;

  @override
  Future<AuthResult> authenticate(
    AuthProviderConfig provider, {
    Uri? backendUrl,
    bool forceLoginPrompt = false,
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
          additionalParameters:
              forceLoginPrompt ? const {'prompt': 'login'} : null,
        ),
      );

      final accessToken = result.accessToken;
      if (accessToken == null) {
        _logger.error(
          'Token exchange succeeded but the access token was null',
        );
        throw const AuthException(
          'IdP returned success but no access token',
          kind: AuthFailureKind.unknown,
        );
      }

      return AuthResult(
        accessToken: accessToken,
        refreshToken: result.refreshToken,
        idToken: result.idToken,
        expiresAt: result.accessTokenExpirationDateTime,
      );
    } on AuthException {
      rethrow;
    } on FlutterAppAuthUserCancelledException catch (e, st) {
      // A deliberate user action, not a fault — so info, which means it is
      // filtered out of a release build. The flow already renders cancellation
      // as a distinct notice rather than an error, so a report can tell the
      // two apart without this record.
      _logger.info(
        'User cancelled sign-in',
        error: e,
        stackTrace: st,
      );
      throw const AuthException(
        'User cancelled sign-in',
        kind: AuthFailureKind.cancelled,
      );
    } on FlutterAppAuthPlatformException catch (e, st) {
      _logger.warning(
        'Sign-in platform exception',
        error: e,
        stackTrace: st,
      );
      throw _classifyAppAuth(e);
    } on PlatformException catch (e, st) {
      _logger.warning(
        'Sign-in channel exception',
        error: e,
        stackTrace: st,
      );
      throw AuthException(
        'Sign-in channel error: ${e.code}',
        kind: AuthFailureKind.unknown,
      );
    } on Exception catch (e, st) {
      _logger.warning(
        'Sign-in failed unexpectedly',
        error: e,
        stackTrace: st,
      );
      throw const AuthException(
        'Unexpected sign-in failure',
        kind: AuthFailureKind.unknown,
      );
    }
  }

  /// Maps a [FlutterAppAuthPlatformException] to an [AuthFailureKind].
  ///
  /// Priority order is deliberate: an IdP-returned RFC 6749 `error` is the
  /// most specific signal (the server told us exactly what was wrong), so it
  /// wins over the plugin's generic `code` and the iOS-only `domain`. When
  /// nothing classifies, falls back to [AuthFailureKind.unknown].
  AuthException _classifyAppAuth(FlutterAppAuthPlatformException e) {
    final oauthError = e.platformErrorDetails.error;
    if (oauthError != null && oauthError.isNotEmpty) {
      return AuthException(
        'IdP rejected sign-in: $oauthError',
        kind: AuthFailureKind.idpRejected,
        oauthError: oauthError,
      );
    }

    switch (e.code) {
      case 'no_browser_available':
        return const AuthException(
          'No browser available',
          kind: AuthFailureKind.noBrowser,
        );
      case 'discovery_failed':
        return const AuthException(
          'Discovery doc unreachable',
          kind: AuthFailureKind.discoveryUnreachable,
        );
    }

    final domain = e.platformErrorDetails.domain;
    if (domain != null) {
      if (domain.startsWith('org.openid.appauth.discovery')) {
        return const AuthException(
          'Discovery doc unreachable',
          kind: AuthFailureKind.discoveryUnreachable,
        );
      }
      if (domain == 'NSURLErrorDomain' ||
          domain.startsWith('org.openid.appauth.network')) {
        return const AuthException(
          'Network failure during sign-in',
          kind: AuthFailureKind.network,
        );
      }
    }

    return const AuthException('Sign-in failed', kind: AuthFailureKind.unknown);
  }

  /// Propagates any [FlutterAppAuth] failure (user cancel, network,
  /// IdP unreachable) to the caller; the local session is the caller's
  /// to preserve or clear based on the platform's logout invariant.
  @override
  Future<void> endSession({
    required String discoveryUrl,
    required String? endSessionEndpoint,
    required String idToken,
    required String clientId,
  }) async {
    await _appAuth.endSession(
      EndSessionRequest(
        idTokenHint: idToken,
        discoveryUrl: discoveryUrl,
        postLogoutRedirectUrl: _redirectUri,
      ),
    );
  }
}
