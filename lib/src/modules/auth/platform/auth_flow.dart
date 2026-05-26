import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;

import 'auth_flow_native.dart' if (dart.library.js_interop) 'auth_flow_web.dart'
    as impl;

/// Result of a successful authentication.
class AuthResult {
  const AuthResult({
    required this.accessToken,
    this.refreshToken,
    this.idToken,
    this.expiresAt,
  });

  final String accessToken;
  final String? refreshToken;
  final String? idToken;
  final DateTime? expiresAt;
}

/// Why an OIDC authentication attempt failed.
///
/// Distinct from HTTP-level auth errors (those use
/// `package:soliplex_agent`'s `AuthException`). This taxonomy captures
/// causes specific to the platform-level OIDC flow — discovery, the
/// browser handoff, and the token exchange.
enum AuthFailureKind {
  /// User dismissed the OAuth browser sheet. Not an error; UI should
  /// render this as a neutral notice, not a red banner.
  cancelled,

  /// Discovery doc fetch failed or returned non-JSON.
  discoveryUnreachable,

  /// Network failure during the auth flow (TLS, DNS, timeout, offline).
  network,

  /// IdP returned an OAuth error on `/authorize` or `/token`. The
  /// specific RFC 6749 code is in [AuthException.oauthError].
  idpRejected,

  /// No installed browser available (Android only).
  noBrowser,

  /// IdP returned success but no access token, or PKCE/state mismatch,
  /// or anything we can't classify.
  unknown,
}

/// Authentication failure from the platform OIDC flow.
class AuthException implements Exception {
  const AuthException(
    this.message, {
    required this.kind,
    this.oauthError,
  });

  final String message;
  final AuthFailureKind kind;

  /// Populated when [kind] is [AuthFailureKind.idpRejected]; carries
  /// the RFC 6749 `error` string (`access_denied`, `invalid_grant`, …).
  final String? oauthError;

  @override
  String toString() =>
      'AuthException($kind${oauthError != null ? ', oauthError: $oauthError' : ''}): $message';
}

/// Thrown when web auth triggers a browser redirect to the IdP.
///
/// On web, [AuthFlow.authenticate] redirects the browser and throws this.
/// Auth completes via the callback screen when the browser returns.
class AuthRedirectInitiated implements Exception {
  const AuthRedirectInitiated();

  @override
  String toString() => 'AuthRedirectInitiated: Browser redirecting to IdP';
}

/// Platform authentication service.
///
/// Native (iOS/macOS/Android): Opens system browser via flutter_appauth.
/// Web: Redirects to backend BFF endpoint which handles the OAuth flow.
abstract interface class AuthFlow {
  /// Authenticate with the given provider.
  ///
  /// [provider] contains the IdP configuration from server discovery.
  /// [backendUrl] is the backend URL for web BFF login (ignored on native).
  ///
  /// Returns [AuthResult] on native, throws [AuthRedirectInitiated] on web.
  Future<AuthResult> authenticate(
    AuthProviderConfig provider, {
    Uri? backendUrl,
  });

  /// End the OIDC session.
  ///
  /// Native: calls flutter_appauth endSession.
  /// Web: redirects to IdP end_session_endpoint if available.
  Future<void> endSession({
    required String discoveryUrl,
    required String? endSessionEndpoint,
    required String idToken,
    required String clientId,
  });
}

/// Creates a platform-appropriate [AuthFlow] implementation.
///
/// [redirectScheme] is the OAuth redirect URI scheme for native platforms
/// (e.g., 'ai.soliplex.client'). Required on native, ignored on web.
AuthFlow createAuthFlow({required String redirectScheme}) =>
    impl.createAuthFlow(redirectScheme: redirectScheme);
