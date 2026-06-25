import 'dart:developer' as dev;

import 'package:shared_preferences/shared_preferences.dart';

import 'auth_tokens.dart';

/// Data persisted per server for session restoration.
sealed class PersistedServer {
  const PersistedServer({
    required this.serverUrl,
    this.alias,
    this.requiresAuth = true,
    this.name,
    this.description,
  });

  factory PersistedServer.fromJson(Map<String, dynamic> json) {
    final serverUrl = Uri.parse(json['serverUrl'] as String);
    final alias = json['alias'] as String?;
    final requiresAuth = json['requiresAuth'] as bool? ?? true;
    final name = json['name'] as String?;
    final description = json['description'] as String?;
    final providerJson = json['provider'] as Map<String, dynamic>?;
    final tokensJson = json['tokens'] as Map<String, dynamic>?;
    if (providerJson != null && tokensJson != null) {
      return AuthenticatedServer(
        serverUrl: serverUrl,
        alias: alias,
        requiresAuth: requiresAuth,
        name: name,
        description: description,
        provider: OidcProvider.fromJson(providerJson),
        tokens: AuthTokens.fromJson(tokensJson),
      );
    }
    if (providerJson != null || tokensJson != null) {
      dev.log('Partial auth data for $serverUrl — treating as unauthenticated');
    }
    return KnownServer(
      serverUrl: serverUrl,
      alias: alias,
      requiresAuth: requiresAuth,
      name: name,
      description: description,
    );
  }

  final Uri serverUrl;
  final String? alias;
  final bool requiresAuth;

  /// Cached human-readable server name, or `null` when unknown.
  final String? name;

  /// Cached brief server description, or `null` when unknown.
  final String? description;

  Map<String, dynamic> toJson();
}

/// A server with active auth credentials.
class AuthenticatedServer extends PersistedServer {
  const AuthenticatedServer({
    required super.serverUrl,
    super.alias,
    super.requiresAuth,
    super.name,
    super.description,
    required this.provider,
    required this.tokens,
  });

  final OidcProvider provider;
  final AuthTokens tokens;

  @override
  Map<String, dynamic> toJson() => {
        'serverUrl': serverUrl.toString(),
        if (alias != null) 'alias': alias,
        'requiresAuth': requiresAuth,
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        'provider': provider.toJson(),
        'tokens': tokens.toJson(),
      };
}

/// A known server without auth credentials.
class KnownServer extends PersistedServer {
  const KnownServer({
    required super.serverUrl,
    super.alias,
    super.requiresAuth,
    super.name,
    super.description,
  });

  @override
  Map<String, dynamic> toJson() => {
        'serverUrl': serverUrl.toString(),
        if (alias != null) 'alias': alias,
        'requiresAuth': requiresAuth,
        if (name != null) 'name': name,
        if (description != null) 'description': description,
      };
}

/// Abstraction for persisting server session data.
abstract class ServerStorage {
  Future<void> save(String serverId, PersistedServer data);
  Future<void> delete(String serverId);
  Future<Map<String, PersistedServer>> loadAll();
}

const _freshInstallKey = 'soliplex_has_launched';

/// Clears stored servers on first launch after a fresh install.
///
/// iOS/macOS Keychain persists across app uninstalls. SharedPreferences
/// does not, so a missing flag means this is a fresh install.
Future<void> clearServersIfFreshInstall(ServerStorage storage) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_freshInstallKey) == true) return;

  try {
    final all = await storage.loadAll();
    for (final serverId in all.keys) {
      await storage.delete(serverId);
    }
  } catch (e, st) {
    dev.log('Failed to clear servers on fresh install',
        error: e, stackTrace: st);
  }
  await prefs.setBool(_freshInstallKey, true);
}
