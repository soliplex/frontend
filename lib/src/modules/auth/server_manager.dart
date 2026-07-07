import 'dart:async';

import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../interfaces/auth_state.dart';
import 'auth_session.dart';
import 'auth_tokens.dart';
import 'server_entry.dart';
import 'server_storage.dart';

final Logger _logger = LogManager.instance.getLogger('soliplex.server_manager');

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

  /// Listeners notified when a server is permanently removed via
  /// [removeServer]. Carries the removal *intent* that the [servers] signal
  /// cannot: an empty-out from [dispose] shrinks the signal identically but
  /// must not notify, so persistent device-local cleanup keys off this event
  /// rather than diffing the signal.
  final List<void Function(String serverId)> _onRemoved = [];

  bool _restoring = false;

  /// Aggregate auth state derived from all server sessions.
  late final ReadonlySignal<AuthState> authState = computed(() {
    return _servers.value.values.any((e) => e.isConnected)
        ? const Authenticated()
        : const Unauthenticated();
  });

  /// A revision marker that bumps on any per-server session-state
  /// change, including transitions that leave the aggregate
  /// [authState] unchanged (e.g. one of several servers flipping to
  /// expired while others stay active). Consumed by GoRouter as a
  /// `refreshListenable` so per-server route guards re-evaluate on
  /// every transition.
  late final ReadonlySignal<List<SessionState>> connectionRevision =
      computed(() => [
            for (final entry in _servers.value.values) entry.auth.session.value,
          ]);

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
    String? name,
    String? description,
  }) {
    final existing = _servers.value[serverId];
    if (existing != null) return existing;

    final String resolvedAlias;
    if (alias != null && _aliases.add(alias)) {
      resolvedAlias = alias;
    } else {
      resolvedAlias = _uniqueAlias(serverUrl);
      if (alias != null) {
        _logger.warning(
          'Alias "$alias" for $serverId collides with an existing alias; '
          'using "$resolvedAlias" instead',
        );
      }
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
      name: name,
      description: description,
    );

    registry.add(connection);
    _servers.value = {..._servers.value, serverId: entry};

    _subscriptions[serverId] = auth.session.subscribe((_) {
      _onSessionChanged(serverId, entry);
    });

    return entry;
  }

  /// Registers a listener fired synchronously when [removeServer] permanently
  /// removes a server. Returns a disposer that unregisters it.
  ///
  /// Dispatch runs over a snapshot of the listeners, so a listener that
  /// unregisters another mid-dispatch does not retract it from the in-flight
  /// round — the unregistered listener still receives the current event.
  /// Subscribers must guard against running after their own disposal.
  void Function() onServerRemoved(void Function(String serverId) listener) {
    _onRemoved.add(listener);
    return () => _onRemoved.remove(listener);
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

    // Snapshot so a listener that unsubscribes itself can't mutate the list
    // mid-iteration. Each dispatch is guarded so one throwing listener can
    // neither strand the others nor abort the rest of removeServer (the storage
    // delete below).
    for (final listener in List.of(_onRemoved)) {
      try {
        listener(serverId);
      } on Object catch (e, st) {
        _logger.error(
          'server-removed listener threw',
          error: e,
          stackTrace: st,
          attributes: {'serverId': serverId},
        );
      }
    }

    _persistQueue[serverId] = (_persistQueue[serverId] ?? Future.value())
        .then((_) => _storage.delete(serverId))
        .catchError((Object e, StackTrace st) {
      _logger.error(
        'Failed to delete stored session for $serverId',
        error: e,
        stackTrace: st,
      );
    });
  }

  /// Restores servers from persistent storage.
  Future<void> restoreServers() async {
    final Map<String, PersistedServer> stored;
    try {
      stored = await _storage.loadAll();
    } catch (e, st) {
      _logger.error('Failed to load stored servers', error: e, stackTrace: st);
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
            name: entry.value.name,
            description: entry.value.description,
          );
          if (entry.value
              case AuthenticatedServer(:final provider, :final tokens)) {
            server.auth.login(provider: provider, tokens: tokens);
          }
        } catch (e, st) {
          _logger.warning(
            'Failed to restore server ${entry.key}',
            error: e,
            stackTrace: st,
          );
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
        case ExpiredSession(:final provider, :final tokens):
          await _storage.save(
            serverId,
            AuthenticatedServer(
              serverUrl: entry.serverUrl,
              alias: entry.alias,
              requiresAuth: entry.requiresAuth,
              name: entry.name,
              description: entry.description,
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
              name: entry.name,
              description: entry.description,
            ),
          );
      }
    }

    _persistQueue[serverId] = (_persistQueue[serverId] ?? Future.value())
        .then((_) => persist())
        .catchError((Object e, StackTrace st) {
      _logger.error(
        'Failed to persist session for $serverId',
        error: e,
        stackTrace: st,
      );
    });
  }
}
