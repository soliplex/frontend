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
  });

  final String accessToken;
  final String? refreshToken;
  final int? expiresIn;

  @override
  String toString() =>
      'WebCallbackSuccess('
      'hasRefreshToken: ${refreshToken != null}, '
      'expiresIn: $expiresIn)';
}

/// Failed web BFF OAuth callback.
class WebCallbackError extends CallbackParams {
  const WebCallbackError({required this.error, this.errorDescription});

  final String error;
  final String? errorDescription;

  @override
  String toString() => 'WebCallbackError(error: $error)';
}

/// No callback parameters detected.
class NoCallbackParams extends CallbackParams {
  const NoCallbackParams();

  @override
  String toString() => 'NoCallbackParams()';
}
