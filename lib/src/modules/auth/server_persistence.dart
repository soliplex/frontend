import 'dart:async';

import 'package:soliplex_logging/soliplex_logging.dart';

import 'auth_tokens.dart';
import 'server_entry.dart';
import 'server_storage.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.server_persistence');

/// Reads and writes the servers' stored records.
///
/// Saves and deletes run one at a time per server and are fire-and-forget: a
/// failure is logged and the queue moves on, so a caller never sees one.
/// [whenPersisted] is how a caller waits for them.
class ServerPersistence {
  ServerPersistence(this._storage);

  final ServerStorage _storage;

  /// Serializes operations per server so a later write never lands first.
  final Map<String, Future<void>> _queue = {};

  /// The records [ServerStorage.loadAll] returns, or null, after logging the
  /// failure, when it throws.
  Future<Map<String, PersistedServer>?> loadAll() async {
    try {
      return await _storage.loadAll();
    } catch (e, st) {
      // A storage failure can quote the stored data it failed to parse.
      _logger.error(
        'Failed to load stored servers',
        attributes: {'failure': describeStorageFailure(e)},
        stackTrace: st,
      );
      return null;
    }
  }

  /// Queues a write of [entry] as its session stands when the write runs:
  /// with its provider and tokens while it has any, an expired session
  /// included, and as a known server once signed out.
  void save(ServerEntry entry) => _enqueue(
        entry.serverId,
        () => _storage.save(entry.serverId, _record(entry)),
        'Failed to persist session for ${entry.serverId}',
      );

  /// Queues the deletion of [serverId]'s record, after any write before it.
  void delete(String serverId) => _enqueue(
        serverId,
        () => _storage.delete(serverId),
        'Failed to delete stored session for $serverId',
      );

  /// Completes when every operation queued so far for [serverId] has settled.
  Future<void> whenPersisted(String serverId) =>
      _queue[serverId] ?? Future.value();

  void _enqueue(
    String serverId,
    Future<void> Function() operation,
    String failureMessage,
  ) {
    _queue[serverId] = (_queue[serverId] ?? Future.value())
        .then((_) => operation())
        .catchError((Object e, StackTrace st) {
      // A save or delete can fail the same way as [loadAll].
      _logger.error(
        failureMessage,
        attributes: {'failure': describeStorageFailure(e)},
        stackTrace: st,
      );
    });
  }

  static PersistedServer _record(ServerEntry entry) =>
      switch (entry.auth.session.value) {
        ActiveSession(:final provider, :final tokens) ||
        ExpiredSession(:final provider, :final tokens) =>
          AuthenticatedServer(
            serverUrl: entry.serverUrl,
            alias: entry.alias,
            requiresAuth: entry.requiresAuth,
            name: entry.name,
            description: entry.description,
            provider: provider,
            tokens: tokens,
          ),
        NoSession() => KnownServer(
            serverUrl: entry.serverUrl,
            alias: entry.alias,
            requiresAuth: entry.requiresAuth,
            name: entry.name,
            description: entry.description,
          ),
      };
}
