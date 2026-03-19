import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import '../../interfaces/auth_state.dart';
import 'auth_session.dart';
import 'auth_tokens.dart';
import 'server_entry.dart';
import 'token_storage.dart';

/// Owns the collection of per-server resources and shared infrastructure.
/// Keeps [ServerRegistry] in sync internally.
class ServerManager {
  ServerManager({
    required SoliplexHttpClient refreshClient,
    required HttpObserver inspector,
    required TokenStorage storage,
  })  : _refreshClient = refreshClient,
        _inspector = inspector,
        _storage = storage {
    _refreshService = TokenRefreshService(httpClient: _refreshClient);
  }

  final SoliplexHttpClient _refreshClient;
  final HttpObserver _inspector;
  final TokenStorage _storage;
  late final TokenRefreshService _refreshService;

  final Signal<Map<String, ServerEntry>> servers =
      Signal<Map<String, ServerEntry>>({});

  final ServerRegistry registry = ServerRegistry();

  /// Tracks signal subscription disposers per server for cleanup.
  final Map<String, void Function()> _subscriptions = {};

  /// Serializes persistence operations per server to prevent race conditions.
  final Map<String, Future<void>> _persistQueue = {};

  /// Aggregate auth state derived from all server sessions.
  late final ReadonlySignal<AuthState> authState = computed(() {
    return servers.value.values.any((e) => e.auth.isAuthenticated)
        ? const Authenticated()
        : const Unauthenticated();
  });

  ServerEntry addServer({required String serverId, required Uri serverUrl}) {
    if (servers.value.containsKey(serverId)) {
      throw StateError('Server "$serverId" already exists');
    }

    final auth = AuthSession(refreshService: _refreshService);

    final httpClient = createAgentHttpClient(
      observers: [_inspector],
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
      serverUrl: serverUrl,
      auth: auth,
      httpClient: httpClient,
      connection: connection,
    );

    registry.add(connection);
    servers.value = {...servers.value, serverId: entry};

    _subscriptions[serverId] = auth.session.subscribe((_) {
      _onSessionChanged(serverId, entry);
    });

    return entry;
  }

  void removeServer(String serverId) {
    final entry = servers.value[serverId];
    if (entry == null) {
      throw StateError('No server entry for "$serverId"');
    }

    _subscriptions.remove(serverId)?.call();

    entry.connection.close();
    entry.httpClient.close();
    registry.remove(serverId);

    final updated = {...servers.value}..remove(serverId);
    servers.value = updated;

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
    for (final entry in stored.entries) {
      try {
        final server = addServer(
          serverId: entry.key,
          serverUrl: entry.value.serverUrl,
        );
        server.auth.login(
          provider: entry.value.provider,
          tokens: entry.value.tokens,
        );
      } catch (e, st) {
        debugPrint('Failed to restore server ${entry.key}: $e\n$st');
      }
    }
  }

  void dispose() {
    for (final id in servers.value.keys.toList()) {
      removeServer(id);
    }
    _refreshClient.close();
  }

  void _onSessionChanged(String serverId, ServerEntry entry) {
    Future<void> persist() async {
      switch (entry.auth.session.value) {
        case ActiveSession(:final provider, :final tokens):
          await _storage.save(
            serverId,
            PersistedServer(
              serverUrl: entry.serverUrl,
              provider: provider,
              tokens: tokens,
            ),
          );
        case NoSession():
          await _storage.delete(serverId);
      }
    }

    _persistQueue[serverId] = (_persistQueue[serverId] ?? Future.value())
        .then((_) => persist())
        .catchError((Object e, StackTrace st) {
      debugPrint('Failed to persist session for $serverId: $e\n$st');
    });
  }
}
