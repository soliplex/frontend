import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show ReadonlySignal, Signal;
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../core/activity_read.dart' show RoomMarkerKey, ServerMarkerKey;
import '../../core/keyed_storage.dart';

export '../../core/activity_read.dart' show RoomMarkerKey, ServerMarkerKey;

final Logger _logger =
    LogManager.instance.getLogger('soliplex.lobby_read_markers');

/// Persists per-room "last seen" timestamps so the lobby can mark rooms with
/// newer activity as unread.
///
/// This is a deliberately simple, *client-side* read model: a room is unread
/// when its last-message time is newer than the moment the user last opened
/// it on this device. There is no server-side read state and no count — just
/// a boolean affordance. Read markers are therefore per-device, and per user:
/// a different user signing in on a shared device sees their own read state.
///
/// Backed by `shared_preferences` (non-sensitive UI state), grained to one blob
/// per `(serverId, userId)` — the lobby loads all of a server's rooms at once,
/// so the blob matches the read-unit. The value is a JSON object `{roomId:
/// ISO-8601 UTC instant}`. Keyed via the shared codec so component separators
/// are unambiguous. A null [userId] (a signed-out or no-auth server) resolves to
/// the shared [unauthenticatedStorageUser] bucket.
abstract final class LobbyReadMarkerStorage {
  static const _prefix = 'soliplex_room_read_marker';

  static String _key(String serverId, String userId) =>
      encodeKey(_prefix, [serverId, userId]);

  /// The read markers (roomId → last-seen instant) for one server and user, or
  /// empty when nothing is stored.
  static Future<Map<String, DateTime>> loadServer({
    required String serverId,
    required String? userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw =
        prefs.getString(_key(serverId, userId ?? unauthenticatedStorageUser));
    if (raw == null || raw.isEmpty) return {};

    final result = <String, DateTime>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _logger.warning(
            'Discarding corrupt room read markers (not a JSON object)');
        return {};
      }
      var skipped = 0;
      decoded.forEach((key, value) {
        if (key is! String || value is! String) {
          skipped++;
          return;
        }
        final at = DateTime.tryParse(value);
        if (at == null) {
          skipped++;
          return;
        }
        result[key] = at.toUtc();
      });
      // Every entry dropped on a non-empty payload is a systemic serialization
      // break, not one stale row, and it silently resets this server's read
      // model (every room flips to unread). Surface it loudly.
      if (skipped > 0 && result.isEmpty) {
        _logger.error('Discarding all $skipped room read markers; none parsed');
      } else if (skipped > 0) {
        _logger.warning('Skipped $skipped malformed room read marker(s)');
      }
    } on FormatException catch (e, st) {
      _logger.warning('Discarding corrupt room read markers',
          error: e, stackTrace: st);
      return {};
    }
    return result;
  }

  /// Persists [markers] (roomId → instant) as the whole blob for the server.
  static Future<void> saveServer({
    required String serverId,
    required String? userId,
    required Map<String, DateTime> markers,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final obj = {
      for (final e in markers.entries) e.key: e.value.toUtc().toIso8601String(),
    };
    await prefs.setString(
        _key(serverId, userId ?? unauthenticatedStorageUser), jsonEncode(obj));
  }

  /// Drops every user's room markers for [serverId]. Only keyed entries are
  /// removed; any pre-keyed entry under the old flat key name is left untouched.
  static Future<void> clearServer(String serverId) async {
    final prefs = await SharedPreferences.getInstance();
    final sweep = serverKeyPrefix(_prefix, serverId);
    for (final k
        in prefs.getKeys().where((k) => k.startsWith(sweep)).toList()) {
      await prefs.remove(k);
    }
  }
}

/// In-memory, reactive source of truth for per-room read markers, shared by the
/// lobby and the room screen. A marker stamped in one screen is visible to the
/// other immediately, because both watch the same [markers] signal — there is
/// no [LobbyReadMarkerStorage] round-trip to race the screens' mount/dispose
/// ordering (which is what let a just-read room show a stale unread dot in the
/// lobby). Backed by [LobbyReadMarkerStorage] for persistence across launches.
///
/// Keys carry the `userId` dimension so multiple servers — each potentially
/// signed in as a different user — coexist in the one signal. The projection to
/// the current user per server lives in the consumers (see
/// `currentUserRoomMarkers`); this model is a dumb, auth-agnostic store.
class RoomReadMarkers {
  final Signal<Map<RoomMarkerKey, DateTime>> _markers = Signal(const {});
  ReadonlySignal<Map<RoomMarkerKey, DateTime>> get markers => _markers;

  /// The `(serverId, userId)` blobs already merged in from disk. Guards against
  /// a re-entrant load clobbering an optimistic in-memory stamp.
  final Set<(String, String)> _loaded = {};

  bool _disposed = false;

  /// The current markers, for a non-reactive read.
  Map<RoomMarkerKey, DateTime> get value => _markers.value;

  /// Loads the `(serverId, userId)` blob once, merging it *under* anything
  /// already stamped in-memory (an early [markRead] before the disk read
  /// returned) so a just-read room isn't clobbered back to unread by the slower
  /// load. Idempotent per `(serverId, userId)`; on failure the guard is released
  /// so a later mount can retry rather than leaving the blob permanently unread.
  Future<void> ensureLoaded({
    required String serverId,
    required String? userId,
  }) async {
    final u = userId ?? unauthenticatedStorageUser;
    if (!_loaded.add((serverId, u))) return;
    final Map<String, DateTime> loaded;
    try {
      loaded = await LobbyReadMarkerStorage.loadServer(
          serverId: serverId, userId: userId);
    } catch (error, st) {
      // Release the guard so a later mount can retry a transient storage error.
      _loaded.remove((serverId, u));
      _logger.warning(
        'Failed to load room read markers',
        error: error,
        stackTrace: st,
      );
      return;
    }
    if (_disposed) return;
    _markers.value = {
      for (final e in loaded.entries)
        (serverId: serverId, userId: u, roomId: e.key): e.value,
      ..._markers.value,
    };
  }

  /// Stamps `(serverId, userId, roomId)` read as of [at] and persists. [at] is
  /// normalized to UTC so the in-memory value equals what a reload yields:
  /// DateTime equality compares the isUtc flag, so a local stamp would be
  /// unequal to its own UTC-parsed reload. The [markers] update is synchronous,
  /// so a screen watching it reacts with no storage round-trip. A null [userId]
  /// resolves to the [unauthenticatedStorageUser] bucket.
  void markRead({
    required String serverId,
    required String? userId,
    required String roomId,
    required DateTime at,
  }) {
    final u = userId ?? unauthenticatedStorageUser;
    _markers.value = {
      ..._markers.value,
      (serverId: serverId, userId: u, roomId: roomId): at.toUtc(),
    };
    unawaited(_persist(serverId, u, userId));
  }

  /// Rewrites the whole `(serverId, userId)` blob. Loads the blob first
  /// (idempotent) so a stamp made before the server's markers were loaded
  /// rewrites the full on-disk set rather than clobbering it down to the single
  /// just-stamped room.
  Future<void> _persist(String serverId, String u, String? userId) async {
    await ensureLoaded(serverId: serverId, userId: userId);
    if (_disposed) return;
    final blob = <String, DateTime>{
      for (final e in _markers.value.entries)
        if (e.key.serverId == serverId && e.key.userId == u)
          e.key.roomId: e.value,
    };
    await LobbyReadMarkerStorage.saveServer(
      serverId: serverId,
      userId: userId,
      markers: blob,
    ).catchError((Object error, StackTrace st) {
      _logger.warning(
        'Failed to persist room read markers',
        error: error,
        stackTrace: st,
      );
    });
  }

  /// Drops every user's markers for [serverId] from memory and disk, so a
  /// removed server's rooms don't read as read if it's re-added under the same
  /// id. The disk sweep runs unconditionally: the in-memory view holds only the
  /// current user's blob per server, so it can't tell whether another user's
  /// (or an unloaded) blob is still on disk.
  void clearServer(String serverId) {
    final next = {..._markers.value}
      ..removeWhere((key, _) => key.serverId == serverId);
    // Reassign only on a real change, to avoid a spurious watcher notification.
    if (next.length != _markers.value.length) _markers.value = next;
    _loaded.removeWhere((pair) => pair.$1 == serverId);
    unawaited(
      LobbyReadMarkerStorage.clearServer(serverId)
          .catchError((Object error, StackTrace st) {
        // Error, not warning: a failed clear leaves stale floors on disk, so a
        // server re-added under the same id reads as already-read (hides unread
        // content), a worse outcome than a missed stamp.
        _logger.error(
          'Failed to clear room read markers for removed server',
          error: error,
          stackTrace: st,
          attributes: {'serverId': serverId},
        );
      }),
    );
  }

  void dispose() {
    _disposed = true;
    _markers.dispose();
  }
}

/// Persists per-server "last seen" timestamps. A server marker floors every
/// room and thread on that server: activity at or before it reads as read, so a
/// single server-level write floors the whole server with no per-room fan-out.
/// Keyed per `(serverId, userId)` so a different user sees their own floor; the
/// value is a single ISO-8601 UTC instant. A null [userId] resolves to the
/// shared [unauthenticatedStorageUser] bucket.
abstract final class ServerReadMarkerStorage {
  static const _prefix = 'soliplex_server_read_marker';

  static String _key(String serverId, String userId) =>
      encodeKey(_prefix, [serverId, userId]);

  /// The server's last-seen instant for [userId], or null when nothing is
  /// stored (or the stored value is unparseable).
  static Future<DateTime?> loadServer({
    required String serverId,
    required String? userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw =
        prefs.getString(_key(serverId, userId ?? unauthenticatedStorageUser));
    if (raw == null || raw.isEmpty) return null;
    final at = DateTime.tryParse(raw);
    if (at == null) {
      _logger.warning('Discarding corrupt server read marker (unparseable)');
      return null;
    }
    return at.toUtc();
  }

  /// Persists [at] as the server's last-seen instant for [userId].
  static Future<void> saveServer({
    required String serverId,
    required String? userId,
    required DateTime at,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(serverId, userId ?? unauthenticatedStorageUser),
      at.toUtc().toIso8601String(),
    );
  }

  /// Drops every user's marker for [serverId] (keyed format).
  static Future<void> clearServer(String serverId) async {
    final prefs = await SharedPreferences.getInstance();
    final sweep = serverKeyPrefix(_prefix, serverId);
    for (final k
        in prefs.getKeys().where((k) => k.startsWith(sweep)).toList()) {
      await prefs.remove(k);
    }
  }
}

/// In-memory, reactive source of truth for per-server read markers, shared by
/// the lobby and the room screen: a marker written to it is visible to both
/// immediately, with no [ServerReadMarkerStorage] round-trip, so a server floor
/// applies to every surface at once. Mirrors [RoomReadMarkers] one level up the
/// hierarchy, keyed `(serverId, userId)`. Backed by [ServerReadMarkerStorage]
/// for persistence across launches.
class ServerReadMarkers {
  final Signal<Map<ServerMarkerKey, DateTime>> _markers = Signal(const {});
  ReadonlySignal<Map<ServerMarkerKey, DateTime>> get markers => _markers;

  final Set<(String, String)> _loaded = {};

  bool _disposed = false;

  /// The current markers, for a non-reactive read.
  Map<ServerMarkerKey, DateTime> get value => _markers.value;

  /// Loads the `(serverId, userId)` marker once, merging it *under* any stamp
  /// already in-memory. Idempotent per `(serverId, userId)`; releases the guard
  /// on failure so a later mount can retry.
  Future<void> ensureLoaded({
    required String serverId,
    required String? userId,
  }) async {
    final u = userId ?? unauthenticatedStorageUser;
    if (!_loaded.add((serverId, u))) return;
    final DateTime? at;
    try {
      at = await ServerReadMarkerStorage.loadServer(
          serverId: serverId, userId: userId);
    } catch (error, st) {
      // Release the guard so a later mount can retry a transient storage error.
      _loaded.remove((serverId, u));
      _logger.warning(
        'Failed to load server read marker',
        error: error,
        stackTrace: st,
      );
      return;
    }
    if (at == null || _disposed) return;
    final key = (serverId: serverId, userId: u);
    if (_markers.value.containsKey(key)) return;
    _markers.value = {..._markers.value, key: at};
  }

  /// Stamps [serverId] read as of [at] for [userId] and persists. [at] is
  /// normalized to UTC (see [RoomReadMarkers.markRead]). A null [userId]
  /// resolves to the [unauthenticatedStorageUser] bucket.
  void markRead({
    required String serverId,
    required String? userId,
    required DateTime at,
  }) {
    final u = userId ?? unauthenticatedStorageUser;
    _markers.value = {
      ..._markers.value,
      (serverId: serverId, userId: u): at.toUtc(),
    };
    unawaited(
      ServerReadMarkerStorage.saveServer(
        serverId: serverId,
        userId: userId,
        at: at.toUtc(),
      ).catchError((Object error, StackTrace st) {
        _logger.warning(
          'Failed to persist server read marker',
          error: error,
          stackTrace: st,
        );
      }),
    );
  }

  /// Drops every user's marker for [serverId] from memory and disk, so a
  /// removed server doesn't floor its rooms if re-added under the same id. The
  /// disk sweep runs unconditionally (see [RoomReadMarkers.clearServer]).
  void clearServer(String serverId) {
    final next = {..._markers.value}
      ..removeWhere((key, _) => key.serverId == serverId);
    // Reassign only on a real change, to avoid a spurious watcher notification.
    if (next.length != _markers.value.length) _markers.value = next;
    _loaded.removeWhere((pair) => pair.$1 == serverId);
    unawaited(
      ServerReadMarkerStorage.clearServer(serverId)
          .catchError((Object error, StackTrace st) {
        // Error, not warning: a failed clear leaves a stale floor on disk, so a
        // server re-added under the same id reads as already-read (hides unread
        // content), a worse outcome than a missed stamp.
        _logger.error(
          'Failed to clear server read marker for removed server',
          error: error,
          stackTrace: st,
          attributes: {'serverId': serverId},
        );
      }),
    );
  }

  void dispose() {
    _disposed = true;
    _markers.dispose();
  }
}
