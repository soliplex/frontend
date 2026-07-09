import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../auth/server_entry.dart';
import 'upload_tracker.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.upload_tracker_registry');

/// Module-scoped registry that hands out one `UploadTracker` per
/// `(serverId, roomId)`.
///
/// Trackers must outlive the widgets that mount them — an upload
/// started on the room-info screen may complete *after* the user taps
/// back, leaving a per-screen tracker without an owning widget. This
/// registry is constructed once in `room_module.dart` (alongside
/// `AgentRuntimeManager` and `RunRegistry`) and threaded into
/// `RoomScreen` and `RoomInfoScreen` so both read from the same
/// underlying tracker instance.
///
/// Eviction: the registry subscribes to `ServerManager.servers` and
/// disposes every tracker whose `serverId` disappears from that map
/// (typically when the user disconnects a server). All remaining
/// trackers are disposed when the registry itself is disposed.
///
/// Lifetime: the registry is process-scoped by design. Production
/// shell teardown does not call [dispose]; an upload started on one
/// screen must survive navigation to another, which the per-server
/// eviction path already handles. [dispose] exists for tests and for
/// the per-tracker cleanup invoked from eviction.
class UploadTrackerRegistry {
  UploadTrackerRegistry({
    required ReadonlySignal<Map<String, ServerEntry>> servers,
  }) : _servers = servers {
    _unsubscribe = _servers.subscribe(_evictRemoved);
  }

  final ReadonlySignal<Map<String, ServerEntry>> _servers;
  final Map<(String, String), UploadTracker> _trackers = {};
  late final void Function() _unsubscribe;
  bool _isDisposed = false;

  /// Returns (or lazily creates) the tracker for the given
  /// `(serverId, roomId)`. Throws [StateError] if the registry has
  /// been disposed.
  ///
  /// Callers should pass a [ServerEntry] whose `serverId` is still
  /// present in the injected `servers` signal; a tracker created for
  /// a server that is never (or no longer) live will not be subject
  /// to the server-removal eviction path.
  ///
  /// Identity is keyed on `(serverId, roomId)` only — assumes
  /// `ServerManager` never hot-swaps an entry's `connection` without
  /// first going through `removeServer` (which evicts the tracker).
  UploadTracker trackerFor({
    required ServerEntry entry,
    required String roomId,
  }) {
    if (_isDisposed) {
      throw StateError('UploadTrackerRegistry has been disposed');
    }
    final key = (entry.serverId, roomId);
    return _trackers.putIfAbsent(
      key,
      () => UploadTracker(api: entry.connection.api, auth: entry.auth),
    );
  }

  void _evictRemoved(Map<String, ServerEntry> snapshot) {
    final liveIds = snapshot.keys.toSet();
    _evictWhere((serverId) => !liveIds.contains(serverId));
  }

  /// Disposes and drops every tracker for [serverId], so a different user
  /// signing in on that server gets a fresh tracker built with their own
  /// api/auth rather than the prior user's. No-op if none are cached.
  void evictServer(String serverId) {
    _evictWhere((id) => id == serverId);
  }

  /// Drops each matching tracker before disposing it — disposal runs real
  /// teardown that can throw, and eviction runs synchronously inside a signal
  /// write (server removal, or a user switch mid-login), where an escape would
  /// unwind the caller and strand the remaining evictions. Removing first keeps
  /// a throw from leaving a disposed tracker referenced; the throw is logged.
  void _evictWhere(bool Function(String serverId) shouldEvict) {
    if (_isDisposed) return;
    final dead = _trackers.entries.where((e) => shouldEvict(e.key.$1)).toList();
    for (final entry in dead) {
      _trackers.remove(entry.key);
      try {
        entry.value.dispose();
      } on Object catch (error, stackTrace) {
        _logger.error(
          'Failed to dispose upload tracker',
          error: error,
          stackTrace: stackTrace,
          attributes: {'serverId': entry.key.$1, 'roomId': entry.key.$2},
        );
      }
    }
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _unsubscribe();
    for (final tracker in _trackers.values) {
      tracker.dispose();
    }
    _trackers.clear();
  }
}
