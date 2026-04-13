import 'callback_params.dart';

/// Parses OAuth callback parameters from URL query params.
///
/// Returns [WebCallbackError] if an `error` key is present,
/// [WebCallbackSuccess] if a token is found (checks both `token`
/// and `access_token` keys), or [NoCallbackParams] otherwise.
CallbackParams parseCallbackParams(Map<String, String> params) {
  if (params.isEmpty) return const NoCallbackParams();

  final error = params['error'];
  if (error != null) {
    return WebCallbackError(
      error: error,
      errorDescription: params['error_description'],
    );
  }

  final accessToken = params['token'] ?? params['access_token'];
  if (accessToken != null) {
    return WebCallbackSuccess(
      accessToken: accessToken,
      refreshToken: params['refresh_token'],
      expiresIn: _parseIntOrNull(params['expires_in']),
    );
  }

  return const NoCallbackParams();
}

/// Extracts query parameters from URL search string and hash fragment.
///
/// Checks [search] first (standard `?key=val`), then falls back to
/// hash-based query params (`#/path?key=val`).
Map<String, String> extractQueryParams({
  required String search,
  required String hash,
}) {
  if (search.isNotEmpty) {
    return Uri.splitQueryString(search.substring(1));
  }

  if (hash.isNotEmpty) {
    final queryIndex = hash.indexOf('?');
    if (queryIndex != -1) {
      return Uri.splitQueryString(hash.substring(queryIndex + 1));
    }
  }

  return {};
}

int? _parseIntOrNull(String? value) {
  if (value == null) return null;
  return int.tryParse(value);
}
