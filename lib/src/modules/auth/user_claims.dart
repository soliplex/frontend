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

/// The label for a signed-in user whose claims name nobody.
const String signedInLabel = 'Signed in';

/// A signed-in identity for display: a [name] and an optional [email].
typedef UserAccount = ({String name, String? email});

/// The display identity in [claims], trying the most specific label first: the
/// full name (`given_name` + `family_name`), then `preferred_username`, then
/// `email`, else [signedInLabel]. The email is `null` when absent or already
/// the name, so the header never renders it twice.
UserAccount accountFromClaims(Map<String, dynamic>? claims) {
  // Read each claim independently: a non-string value is treated as absent so
  // one malformed field can't discard its valid siblings.
  String claim(String key) {
    final value = claims?[key];
    return value is String ? value : '';
  }

  final given = claim('given_name');
  final family = claim('family_name');
  final preferred = claim('preferred_username').trim();
  final email = claim('email').trim();
  final full = '$given $family'.trim();
  final hasName = full.isNotEmpty || preferred.isNotEmpty;
  final name = [full, preferred, email]
      .firstWhere((s) => s.isNotEmpty, orElse: () => signedInLabel);
  return (name: name, email: hasName && email.isNotEmpty ? email : null);
}
