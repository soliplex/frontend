/// Callback parameters extracted from the auth callback URL.
sealed class CallbackParams {
  const CallbackParams();
}

/// Successful web BFF OAuth callback with tokens.
class WebCallbackSuccess extends CallbackParams {
  const WebCallbackSuccess({
    required this.accessToken,
    this.refreshToken,
    this.expiresIn,
    this.idToken,
  });

  final String accessToken;
  final String? refreshToken;
  final int? expiresIn;

  /// OIDC ID Token. Required as `id_token_hint` for RP-Initiated
  /// Logout to deterministically end the IdP SSO session. Null when the
  /// callback carries no ID token: the backend predates v0.82.3 / v0.83.3, its
  /// `scope` lacks `openid`, or the provider returned none.
  final String? idToken;

  @override
  String toString() => 'WebCallbackSuccess('
      'hasRefreshToken: ${refreshToken != null}, '
      'expiresIn: $expiresIn, '
      'hasIdToken: ${idToken != null})';
}

/// Failed web BFF OAuth callback.
class WebCallbackError extends CallbackParams {
  const WebCallbackError({
    required this.error,
    this.errorDescription,
  });

  final String error;
  final String? errorDescription;

  @override
  String toString() => 'WebCallbackError(error: $error)';
}

/// A web sign-in callback whose query could not be decoded.
class WebCallbackMalformed extends CallbackParams {
  const WebCallbackMalformed();

  @override
  String toString() => 'WebCallbackMalformed()';
}

/// No callback parameters detected.
class NoCallbackParams extends CallbackParams {
  const NoCallbackParams();

  @override
  String toString() => 'NoCallbackParams()';
}
