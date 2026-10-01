import 'callback_params.dart';

/// Parses OAuth callback parameters from URL query params.
///
/// Returns [WebCallbackError] if an `error` key is present,
/// [WebCallbackSuccess] if a token is found (checks the `token` key), or
/// [NoCallbackParams] otherwise.
CallbackParams parseCallbackParams(Map<String, String> params) {
  if (params.isEmpty) return const NoCallbackParams();

  final error = params['error'];
  if (error != null) {
    return WebCallbackError(
      error: error,
      errorDescription: params['error_description'],
    );
  }

  final accessToken = params['token'];
  if (accessToken != null) {
    return WebCallbackSuccess(
      accessToken: accessToken,
      refreshToken: params['refresh_token'],
      expiresIn: _parseIntOrNull(params['expires_in']),
      idToken: params['id_token'],
    );
  }

  return const NoCallbackParams();
}

/// The sign-in callback route, where the backend puts the tokens after a `?`.
const authCallbackHash = '#/auth/callback';

/// The query of a sign-in callback [hash], or `null` when [hash] is not
/// `#/auth/callback?…`.
String? callbackQueryFromHash(String hash) {
  const prefix = '$authCallbackHash?';
  return hash.startsWith(prefix) ? hash.substring(prefix.length) : null;
}

/// The URL to replace the page's with on a page load, so it starts with no
/// query, not in the address bar ([search]) and not in the hash route, or
/// `null` when it carries none. The callback query holds tokens; any other
/// query is set by in-app navigation, so a page load starts with no query: an
/// outside link can't supply one that way. It starts with [origin], so a
/// [pathname] that reads as another host (`//evil.example/`) cannot make it
/// cross-origin.
String? urlWithoutQueries({
  required String origin,
  required String pathname,
  required String search,
  required String hash,
}) {
  final queryStart = hash.indexOf('?');
  if (search.isEmpty && queryStart == -1) return null;
  final route = queryStart == -1 ? hash : hash.substring(0, queryStart);
  return '$origin$pathname$route';
}

/// A captured sign-in callback, and whether it was still in the URL because
/// `web/index.html` lacks the script that moves it out before the app loads.
typedef CapturedCallback = ({CallbackParams params, bool scriptMissing});

/// Captures the sign-in callback from the query `web/index.html` stashed
/// ([stashedQuery]), falling back to the current URL's [hash].
CapturedCallback captureCallback({
  required String? stashedQuery,
  required String hash,
}) {
  if (stashedQuery != null) {
    return (
      params: parseCallbackParams(Uri.splitQueryString(stashedQuery)),
      scriptMissing: false,
    );
  }
  final query = callbackQueryFromHash(hash);
  if (query == null) {
    return (params: const NoCallbackParams(), scriptMissing: false);
  }
  return (
    params: parseCallbackParams(Uri.splitQueryString(query)),
    scriptMissing: true,
  );
}

int? _parseIntOrNull(String? value) {
  if (value == null) return null;
  return int.tryParse(value);
}
