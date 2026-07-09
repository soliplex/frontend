import 'dart:async' show unawaited;

import 'package:soliplex_logging/soliplex_logging.dart';

import '../modules/auth/return_to_storage.dart';
import '../modules/auth/server_manager.dart';
import '../modules/lobby/lobby_read_markers.dart'
    show RoomReadMarkers, ServerReadMarkers;
import '../modules/room/document_selections.dart';
import '../modules/room/thread_anchor_storage.dart';
import '../modules/room/thread_read_markers.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.removed_server_cleanup');

/// Drops a removed server's device-local state so re-adding it under the same
/// id doesn't resurrect stale read state, a misplaced thread divider, an unsent
/// draft, or its in-memory document filter selections. Server ids derive from
/// the URL, so a re-add reuses the id.
///
/// Owned by [RoomAppModule] (like [UploadTrackerRegistry]) rather than a screen
/// because removal fires from surfaces that don't mount the lobby — notably the
/// home screen's server list. Registering on [ServerManager.onServerRemoved] at
/// module scope runs the cleanup for every removal path across the whole app
/// session. The shared in-memory read-marker models are the same instances the
/// lobby and room screens watch, so clearing them updates a mounted screen
/// reactively too.
///
/// Only a genuine [ServerManager.removeServer] clears disk state. Shell
/// teardown empties the servers signal without firing the removal event, so
/// stored sessions survive to the next launch regardless of module dispose
/// ordering.
class RemovedServerCleanup {
  RemovedServerCleanup({
    required ServerManager serverManager,
    required RoomReadMarkers roomReadMarkers,
    required ServerReadMarkers serverReadMarkers,
    required DocumentSelections documentSelections,
  })  : _roomReadMarkers = roomReadMarkers,
        _serverReadMarkers = serverReadMarkers,
        _documentSelections = documentSelections {
    _unsubscribe = serverManager.onServerRemoved(_clearServer);
  }

  final RoomReadMarkers _roomReadMarkers;
  final ServerReadMarkers _serverReadMarkers;
  final DocumentSelections _documentSelections;
  late final void Function() _unsubscribe;
  bool _isDisposed = false;

  /// Runs synchronously inside [ServerManager.removeServer] via the
  /// onServerRemoved dispatch. Every clear is isolated so one failure can't
  /// strand the others: the in-memory clears run guarded and the static stores
  /// run fire-and-forget with their throws caught and logged per store.
  void _clearServer(String id) {
    // onServerRemoved dispatches over a snapshot, so if a preceding listener
    // synchronously tore down this cleanup, this callback still fires from that
    // snapshot. A disposed cleanup does no work; the silent return is expected.
    if (_isDisposed) return;
    _clearInMemory(
        () => _serverReadMarkers.clearServer(id), 'server read marker', id);
    _clearInMemory(
        () => _roomReadMarkers.clearServer(id), 'room read markers', id);
    _clearInMemory(
        () => _documentSelections.clearServer(id), 'document selections', id);
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
        // Warning, not error: a stale anchor only misplaces a "New messages"
        // divider (cosmetic), unlike the thread-marker clear above whose
        // failure hides unread content.
        _logger.warning(
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

  /// Runs a synchronous in-memory clear, logging any throw so it can't strand
  /// the sibling clears that follow it in [_clearServer].
  void _clearInMemory(void Function() clear, String what, String id) {
    try {
      clear();
    } on Object catch (error, st) {
      _logger.error(
        'Failed to clear $what for removed server',
        error: error,
        stackTrace: st,
        attributes: {'serverId': id},
      );
    }
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _unsubscribe();
  }
}
