import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import '../../interfaces/auth_state.dart';
import 'auth_session.dart';
import 'auth_tokens.dart';
import 'server_entry.dart';
import 'server_storage.dart';

typedef HttpClientFactory = SoliplexHttpClient Function({
  String? Function()? getToken,
  TokenRefresher? tokenRefresher,
});

typedef AuthSessionFactory = AuthSession Function();

/// Owns the collection of per-server resources and shared infrastructure.
/// Keeps [ServerRegistry] in sync internally.
class ServerManager {
  ServerManager({
    required AuthSessionFactory authFactory,
    required HttpClientFactory clientFactory,
    required ServerStorage storage,
  })  : _authFactory = authFactory,
        _clientFactory = clientFactory,
        _storage = storage;

  final AuthSessionFactory _authFactory;
  final HttpClientFactory _clientFactory;
  final ServerStorage _storage;

  final Signal<Map<String, ServerEntry>> _servers =
      Signal<Map<String, ServerEntry>>({});
  ReadonlySignal<Map<String, ServerEntry>> get servers => _servers;

  final ServerRegistry registry = ServerRegistry();

  /// Tracks signal subscription disposers per server for cleanup.
  final Map<String, void Function()> _subscriptions = {};

  /// Serializes persistence operations per server to prevent race conditions.
  final Map<String, Future<void>> _persistQueue = {};

  /// Tracks in-use aliases to ensure uniqueness.
  final Set<String> _aliases = {};

  bool _restoring = false;

  /// Aggregate auth state derived from all server sessions.
  late final ReadonlySignal<AuthState> authState = computed(() {
    return _servers.value.values.any((e) => e.isConnected)
        ? const Authenticated()
        : const Unauthenticated();
  });

  String _uniqueAlias(Uri serverUrl) {
    final base = aliasFromUrl(serverUrl);
    if (_aliases.add(base)) return base;
    for (var i = 2;; i++) {
      final candidate = '$base-$i';
      if (_aliases.add(candidate)) return candidate;
    }
  }

  ServerEntry? entryByAlias(String alias) {
    for (final entry in _servers.value.values) {
      if (entry.alias == alias) return entry;
    }
    return null;
  }

  ServerEntry addServer({
    required String serverId,
    required Uri serverUrl,
    bool requiresAuth = true,
    String? alias,
  }) {
    final existing = _servers.value[serverId];
    if (existing != null) return existing;

    final String resolvedAlias;
    if (alias != null && _aliases.add(alias)) {
      resolvedAlias = alias;
    } else {
      resolvedAlias = _uniqueAlias(serverUrl);
    }

    final auth = _authFactory();

    final httpClient = _clientFactory(
      getToken: () => auth.accessToken,
      tokenRefresher: auth,
    );

    final connection = ServerConnection.create(
      serverId: serverId,
      serverUrl: serverUrl.toString(),
      httpClient: httpClient,
    );

    final entry = ServerEntry(
      serverId: serverId,
      alias: resolvedAlias,
      serverUrl: serverUrl,
      auth: auth,
      httpClient: httpClient,
      connection: connection,
      requiresAuth: requiresAuth,
    );

    registry.add(connection);
    _servers.value = {..._servers.value, serverId: entry};

    _subscriptions[serverId] = auth.session.subscribe((_) {
      _onSessionChanged(serverId, entry);
    });

    return entry;
  }

  void removeServer(String serverId) {
    final entry = _servers.value[serverId];
    if (entry == null) {
      throw StateError('No server entry for "$serverId"');
    }

    _aliases.remove(entry.alias);
    _subscriptions.remove(serverId)?.call();

    entry.connection.close();
    entry.httpClient.close();
    registry.remove(serverId);

    final updated = {..._servers.value}..remove(serverId);
    _servers.value = updated;

    _persistQueue[serverId] = (_persistQueue[serverId] ?? Future.value())
        .then((_) => _storage.delete(serverId))
        .catchError((Object e, StackTrace st) {
      debugPrint('Failed to delete stored session for $serverId: $e\n$st');
    });
  }

  /// Restores servers from persistent storage.
  Future<void> restoreServers() async {
    final Map<String, PersistedServer> stored;
    try {
      stored = await _storage.loadAll();
    } catch (e, st) {
      debugPrint('Failed to load stored servers: $e\n$st');
      return;
    }
    _restoring = true;
    try {
      for (final entry in stored.entries) {
        try {
          final server = addServer(
            serverId: entry.key,
            serverUrl: entry.value.serverUrl,
            requiresAuth: entry.value.requiresAuth,
            alias: entry.value.alias,
          );
          if (entry.value
              case AuthenticatedServer(:final provider, :final tokens)) {
            server.auth.login(provider: provider, tokens: tokens);
          }
        } catch (e, st) {
          debugPrint('Failed to restore server ${entry.key}: $e\n$st');
        }
      }
    } finally {
      _restoring = false;
    }
  }

  void dispose() {
    for (final entry in _servers.value.entries) {
      _subscriptions.remove(entry.key)?.call();
      entry.value.connection.close();
      entry.value.httpClient.close();
      registry.remove(entry.key);
    }
    _aliases.clear();
    _servers.value = {};
  }

  void _onSessionChanged(String serverId, ServerEntry entry) {
    if (_restoring) return;
    Future<void> persist() async {
      switch (entry.auth.session.value) {
        case ActiveSession(:final provider, :final tokens):
          await _storage.save(
            serverId,
            AuthenticatedServer(
              serverUrl: entry.serverUrl,
              alias: entry.alias,
              requiresAuth: entry.requiresAuth,
              provider: provider,
              tokens: tokens,
            ),
          );
        case NoSession():
          await _storage.save(
            serverId,
            KnownServer(
              serverUrl: entry.serverUrl,
              alias: entry.alias,
              requiresAuth: entry.requiresAuth,
            ),
          );
      }
    }

    _persistQueue[serverId] = (_persistQueue[serverId] ?? Future.value())
        .then((_) => persist())
        .catchError((Object e, StackTrace st) {
      debugPrint('Failed to persist session for $serverId: $e\n$st');
    });
  }
}
