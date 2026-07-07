import 'dart:convert';

/// Extracts a stable per-user identity from a JWT [accessToken].
///
/// Returns `"<iss>#<sub>"` when the token is a JWT whose payload carries
/// non-empty `iss` and `sub` string claims, else `null`. `sub` is the IdP's
/// stable subject id; `iss` disambiguates subjects across issuers on one server.
///
/// Decode-only: the backend already validated the token cryptographically, so
/// this reads claims purely to bucket device-local state. Never throws.
String? accessTokenIdentity(String accessToken) {
  final segments = accessToken.split('.');
  if (segments.length < 2) return null;
  try {
    final payload =
        utf8.decode(base64Url.decode(base64Url.normalize(segments[1])));
    final decoded = jsonDecode(payload);
    if (decoded is! Map<String, dynamic>) return null;
    final iss = decoded['iss'];
    final sub = decoded['sub'];
    if (iss is! String || iss.isEmpty) return null;
    if (sub is! String || sub.isEmpty) return null;
    return '$iss#$sub';
  } on Object {
    return null;
  }
}
