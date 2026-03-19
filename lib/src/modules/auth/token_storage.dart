import 'auth_tokens.dart';

/// Data persisted per server for session restoration.
class PersistedServer {
  const PersistedServer({
    required this.serverUrl,
    required this.provider,
    required this.tokens,
  });

  factory PersistedServer.fromJson(Map<String, dynamic> json) {
    return PersistedServer(
      serverUrl: Uri.parse(json['serverUrl'] as String),
      provider: OidcProvider.fromJson(json['provider'] as Map<String, dynamic>),
      tokens: AuthTokens.fromJson(json['tokens'] as Map<String, dynamic>),
    );
  }

  final Uri serverUrl;
  final OidcProvider provider;
  final AuthTokens tokens;

  Map<String, dynamic> toJson() => {
        'serverUrl': serverUrl.toString(),
        'provider': provider.toJson(),
        'tokens': tokens.toJson(),
      };
}

/// Abstraction for persisting auth tokens per server.
abstract class TokenStorage {
  Future<void> save(String serverId, PersistedServer data);
  Future<void> delete(String serverId);
  Future<Map<String, PersistedServer>> loadAll();
}
