import 'package:signals_flutter/signals_flutter.dart';

import '../auth/server_entry.dart';
import 'per_server_cache.dart';
import 'upload_tracker.dart';

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
  }) : _trackers = PerServerCache(
          servers: servers,
          disposeValue: (tracker) => tracker.dispose(),
          what: 'upload tracker',
        );

  final PerServerCache<String, UploadTracker> _trackers;

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
  }) =>
      _trackers.putIfAbsent(
        entry.serverId,
        roomId,
        () => UploadTracker(api: entry.connection.api, auth: entry.auth),
      );

  /// Disposes and drops every tracker for [serverId], so a different user
  /// signing in on that server starts with an empty tracker instead of
  /// inheriting the prior user's in-flight and completed uploads. No-op if
  /// none are cached.
  void evictServer(String serverId) => _trackers.evictServer(serverId);

  void dispose() => _trackers.dispose();
}
