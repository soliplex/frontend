/// OIDC provider identity for a server connection.
class OidcProvider {
  const OidcProvider({
    required this.discoveryUrl,
    required this.clientId,
  });

  factory OidcProvider.fromJson(Map<String, dynamic> json) {
    return OidcProvider(
      discoveryUrl: json['discoveryUrl'] as String,
      clientId: json['clientId'] as String,
    );
  }

  final String discoveryUrl;
  final String clientId;

  Map<String, dynamic> toJson() => {
        'discoveryUrl': discoveryUrl,
        'clientId': clientId,
      };
}

/// In-memory token cache.
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.idToken,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      idToken: json['idToken'] as String?,
    );
  }

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String? idToken;

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt.toIso8601String(),
        if (idToken != null) 'idToken': idToken,
      };
}

/// Single source of truth for auth session state.
/// Makes invalid states unrepresentable — provider and tokens are
/// always present together or both absent.
sealed class SessionState {
  const SessionState();
}

final class NoSession extends SessionState {
  const NoSession();
}

final class ActiveSession extends SessionState {
  const ActiveSession({
    required this.provider,
    required this.tokens,
  });

  final OidcProvider provider;
  final AuthTokens tokens;
}
