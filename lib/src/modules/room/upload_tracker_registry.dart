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
/// Eviction ([PerServerCache]): a tracker is disposed when its server is
/// removed, when [evictServer] drops it (a different user signed in), and
/// when the registry is disposed, which the room module does on its own
/// disposal.
class UploadTrackerRegistry {
  UploadTrackerRegistry({
    required ReadonlySignal<Map<String, ServerEntry>> servers,
  }) : _trackers = PerServerCache(
          servers: servers,
          disposeValue: (tracker) => tracker.dispose(),
        );

  final PerServerCache<String, UploadTracker> _trackers;

  /// Returns (or lazily creates) the tracker for [entry]'s server and
  /// [roomId]. Throws [StateError] if the registry has been disposed.
  UploadTracker trackerFor({
    required ServerEntry entry,
    required String roomId,
  }) =>
      _trackers.putIfAbsent(
        entry,
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
