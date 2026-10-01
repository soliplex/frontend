import 'dart:convert';

/// The claims in [jwt]'s payload, or `null` when [jwt] is not a JWT whose
/// payload is a JSON object.
///
/// Decode-only: the signature is never checked. The claims only bucket
/// device-local state and label the account, and the backend authenticates
/// every request itself. Never throws.
Map<String, dynamic>? decodeJwtClaims(String jwt) {
  final segments = jwt.split('.');
  if (segments.length < 2) return null;
  try {
    final payload =
        utf8.decode(base64Url.decode(base64Url.normalize(segments[1])));
    final decoded = jsonDecode(payload);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on Object {
    return null;
  }
}

/// A stable per-user identity, `"<iss>#<sub>"`, from [claims], or `null`
/// unless both are non-empty strings. `sub` is the IdP's stable subject id;
/// `iss` disambiguates subjects across issuers on one server.
String? identityFromClaims(Map<String, dynamic> claims) {
  final iss = claims['iss'];
  final sub = claims['sub'];
  if (iss is! String || iss.isEmpty) return null;
  if (sub is! String || sub.isEmpty) return null;
  return '$iss#$sub';
}
