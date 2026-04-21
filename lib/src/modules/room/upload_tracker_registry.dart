import 'package:signals_flutter/signals_flutter.dart';

import '../auth/server_entry.dart';
import 'upload_tracker.dart';

/// Module-scoped registry that hands out one `UploadTracker` per
/// `(serverId, roomId)`.
///
/// Trackers must outlive the widgets that mount them — an upload
/// started on the room-info screen may complete *after* the user taps
/// back, which would orphan a per-screen tracker. This registry is
/// constructed once in `room_module.dart` (alongside
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
      () => UploadTracker(api: entry.connection.api),
    );
  }

  void _evictRemoved(Map<String, ServerEntry> snapshot) {
    if (_isDisposed) return;
    final liveIds = snapshot.keys.toSet();
    final dead =
        _trackers.entries.where((e) => !liveIds.contains(e.key.$1)).toList();
    for (final entry in dead) {
      entry.value.dispose();
      _trackers.remove(entry.key);
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
