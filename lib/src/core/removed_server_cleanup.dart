import 'dart:async' show unawaited;

import 'package:soliplex_agent/soliplex_agent.dart' show ReadonlySignal;
import 'package:soliplex_logging/soliplex_logging.dart';

import '../modules/auth/return_to_storage.dart';
import '../modules/auth/server_entry.dart';
import '../modules/lobby/lobby_read_markers.dart'
    show RoomReadMarkers, ServerReadMarkers;
import '../modules/room/thread_anchor_storage.dart';
import '../modules/room/thread_read_markers.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.removed_server_cleanup');

/// Drops a removed server's device-local state so re-adding it under the same
/// id doesn't resurrect stale read state, a misplaced thread divider, or an
/// unsent draft. Server ids derive from the URL, so a re-add reuses the id.
///
/// Owned by [RoomAppModule] (like [UploadTrackerRegistry]) rather than a screen
/// because removal fires from surfaces that don't mount the lobby — notably the
/// home screen's server list. Subscribing to [ServerManager.servers] at module
/// scope runs the cleanup for every removal path across the whole app session.
/// The shared in-memory read-marker models are the same instances the lobby and
/// room screens watch, so clearing them updates a mounted screen reactively too.
///
/// [dispose] must run before [ServerManager.dispose] empties the servers signal
/// on shell teardown: that empty-out is a set transition this class would
/// otherwise read as a mass removal and wipe every server's state, even though
/// teardown keeps stored sessions for the next launch. [RoomAppModule] is
/// disposed before the auth module (reverse registration order), so its
/// `onDispose` unsubscribes in time.
class RemovedServerCleanup {
  RemovedServerCleanup({
    required ReadonlySignal<Map<String, ServerEntry>> servers,
    required RoomReadMarkers roomReadMarkers,
    required ServerReadMarkers serverReadMarkers,
  })  : _roomReadMarkers = roomReadMarkers,
        _serverReadMarkers = serverReadMarkers {
    // Seed the baseline before subscribing: the signals library fires the
    // callback synchronously with the current value, and _onServersChanged
    // reads _knownIds on that first fire. Seeding it to the current ids makes
    // that fire a no-op (nothing diffs as removed) and avoids reading the late
    // field before it is assigned.
    _knownIds = servers.value.keys.toSet();
    _unsubscribe = servers.subscribe(_onServersChanged);
  }

  final RoomReadMarkers _roomReadMarkers;
  final ServerReadMarkers _serverReadMarkers;
  late Set<String> _knownIds;
  late final void Function() _unsubscribe;
  bool _isDisposed = false;

  void _onServersChanged(Map<String, ServerEntry> servers) {
    if (_isDisposed) return;
    final nextIds = servers.keys.toSet();
    final removed = _knownIds.difference(nextIds);
    _knownIds = nextIds;
    for (final id in removed) {
      _clearServer(id);
    }
  }

  /// Runs synchronously inside the servers-signal write (the subscription fires
  /// during [ServerManager.removeServer]). The in-memory model clears are
  /// synchronous map/signal updates that also persist themselves fire-and-forget
  /// with their own failure logging; the static stores are awaited off the
  /// microtask queue with their throws caught here so one failure can't strand
  /// the others or unwind the signal write.
  void _clearServer(String id) {
    _serverReadMarkers.clearServer(id);
    _roomReadMarkers.clearServer(id);
    unawaited(
      ThreadReadMarkerStorage.clearServer(id)
          .catchError((Object error, StackTrace st) {
        // Error, not warning: a failed clear leaves stale thread floors on
        // disk, so a server re-added under the same id reads as already-read
        // (hides unread content), a worse outcome than a missed stamp.
        _logger.error(
          'Failed to clear thread read markers for removed server',
          error: error,
          stackTrace: st,
          attributes: {'serverId': id},
        );
      }),
    );
    unawaited(
      ThreadAnchorStorage.clearServer(id)
          .catchError((Object error, StackTrace st) {
        // Error to match the thread-marker clear it mirrors: a stale anchor
        // only misplaces a divider, but a systemic write failure here would
        // also fail that clear, so surface both at the same level.
        _logger.error(
          'Failed to clear thread anchors for removed server',
          error: error,
          stackTrace: st,
          attributes: {'serverId': id},
        );
      }),
    );
    unawaited(
      ReturnToStorage.clearServer(id).catchError((Object error, StackTrace st) {
        // Warning: a surviving draft self-expires after 24h and can only
        // resurface in a re-added room, so it's lower stakes than a marker.
        _logger.warning(
          'Failed to clear composer drafts for removed server',
          error: error,
          stackTrace: st,
          attributes: {'serverId': id},
        );
      }),
    );
    // The inactivity-logout flag is deliberately not cleared. It forces
    // prompt=login on the next connect (see ConnectFlow), so a server removed
    // while inactivity-logged-out must keep it: clearing it would let a re-add
    // under the same id reuse a silent IdP session and skip the forced re-login.
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _unsubscribe();
  }
}
