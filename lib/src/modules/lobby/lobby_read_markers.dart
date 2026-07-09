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
    final raw = prefs.getString(_key(serverId, storageUser(userId)));
    if (raw == null || raw.isEmpty) return {};

    final result = <String, DateTime>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        // A non-empty payload that isn't a JSON object wipes this server's whole
        // read model (every room flips to unread) — a systemic serialization
        // break, not one stale row. Same severity as the all-entries-dropped
        // case below.
        _logger.error(
          'Discarding corrupt room read markers (not a JSON object)',
          attributes: {
            'serverId': serverId,
            'userId': storageUser(userId),
          },
        );
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
      final attributes = {
        'serverId': serverId,
        'userId': storageUser(userId),
      };
      if (skipped > 0 && result.isEmpty) {
        _logger.error('Discarding all $skipped room read markers; none parsed',
            attributes: attributes);
      } else if (skipped > 0) {
        _logger.warning('Skipped $skipped malformed room read marker(s)',
            attributes: attributes);
      }
    } on FormatException catch (e, st) {
      // Unparseable JSON wipes this server's whole read model; surface as loudly
      // as the all-entries-dropped case (raw is non-empty here).
      _logger.error(
        'Discarding corrupt room read markers',
        error: e,
        stackTrace: st,
        attributes: {
          'serverId': serverId,
          'userId': storageUser(userId),
        },
      );
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
    await prefs.setString(_key(serverId, storageUser(userId)), jsonEncode(obj));
  }

  /// Drops every user's room markers for [serverId]. Sweeps only keys under this
  /// class's `(serverId, userId)` prefix; unrelated keys are untouched.
  static Future<void> clearServer(String serverId) async {
    final prefs = await SharedPreferences.getInstance();
    final sweep = serverKeyPrefix(_prefix, serverId);
    for (final k
        in prefs.getKeys().where((k) => k.startsWith(sweep)).toList()) {
      await prefs.remove(k);
    }
  }

  /// Removes [roomId] from every user's blob for [serverId], leaving sibling
  /// rooms intact. Sweeps this class's `(serverId, userId)` keys; unrelated keys
  /// are untouched.
  static Future<void> clearRoom(String serverId, String roomId) async {
    final prefs = await SharedPreferences.getInstance();
    final sweep = serverKeyPrefix(_prefix, serverId);
    for (final k
        in prefs.getKeys().where((k) => k.startsWith(sweep)).toList()) {
      final raw = prefs.getString(k);
      if (raw == null || raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map || !decoded.containsKey(roomId)) continue;
        decoded.remove(roomId);
        await prefs.setString(k, jsonEncode(decoded));
      } on FormatException catch (error, st) {
        // A corrupt blob can't be stripped, so the room's marker survives here;
        // the next loadServer discards the whole blob and re-logs. Log so this
        // skip isn't silent, matching the other corruption sites in this class.
        _logger.warning(
          'Skipped corrupt room read marker blob while clearing a room',
          error: error,
          stackTrace: st,
          attributes: {'serverId': serverId, 'roomId': roomId, 'key': k},
        );
        continue;
      }
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

  /// `(serverId, userId)` blobs whose disk load has completed. A completed key
  /// means the in-memory map already holds that blob's full on-disk set, so a
  /// rewrite of it (see [_persist]) can't shrink what's on disk.
  final Set<ServerMarkerKey> _loaded = {};

  /// In-flight loads per `(serverId, userId)`, so concurrent callers await the
  /// same disk read instead of each racing a partial in-memory view onto disk.
  final Map<ServerMarkerKey, Future<void>> _loadTasks = {};

  /// Per-server clear epoch, bumped by [clearServer]. A suspended [_load] or
  /// [_persist] captures it before its `await` and, on resume, discards its work
  /// if the epoch moved — so a clear that lands mid-flight can't be undone by the
  /// op re-inserting a swept blob into memory or rewriting it to disk (which
  /// would hide unread content on a same-id re-add). Keyed per server so clearing
  /// one server never invalidates another's in-flight write.
  final Map<String, int> _generation = {};

  bool _disposed = false;

  /// The current markers, for a non-reactive read.
  Map<RoomMarkerKey, DateTime> get value => _markers.value;

  /// Loads the `(serverId, userId)` blob once, merging it *under* anything
  /// already stamped in-memory (an early [markRead] before the disk read
  /// returned) so a just-read room isn't clobbered back to unread by the slower
  /// load. Concurrent calls await the same in-flight load; a failed load leaves
  /// the key unloaded so a later mount retries rather than wedging it unread.
  Future<void> ensureLoaded({
    required String serverId,
    required String? userId,
  }) {
    final key = (serverId: serverId, userId: storageUser(userId));
    if (_loaded.contains(key)) return Future<void>.value();
    return _loadTasks[key] ??= _load(serverId, userId, key);
  }

  Future<void> _load(
      String serverId, String? userId, ServerMarkerKey key) async {
    final gen = _generation[serverId] ?? 0;
    try {
      final loaded = await LobbyReadMarkerStorage.loadServer(
          serverId: serverId, userId: userId);
      // A clear (or dispose) landed while this load was in flight; its blob was
      // swept, so committing it now would resurrect the cleared state.
      if (_disposed || gen != (_generation[serverId] ?? 0)) return;
      _markers.value = {
        for (final e in loaded.entries)
          (serverId: serverId, userId: key.userId, roomId: e.key): e.value,
        ..._markers.value,
      };
      _loaded.add(key);
    } catch (error, st) {
      _logger.warning(
        'Failed to load room read markers',
        error: error,
        stackTrace: st,
      );
    } finally {
      // Only clear our own task slot: a stale epoch's [clearServer] already
      // removed it, and a re-add may have registered a newer load under this key.
      if (gen == (_generation[serverId] ?? 0)) _loadTasks.remove(key);
    }
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
    final u = storageUser(userId);
    _markers.value = {
      ..._markers.value,
      (serverId: serverId, userId: u, roomId: roomId): at.toUtc(),
    };
    unawaited(_persist(serverId, u, userId));
  }

  /// Rewrites the whole `(serverId, userId)` blob. Waits for the blob's load to
  /// complete first, so a stamp made before or during the load rewrites the
  /// full on-disk set rather than shrinking it to the just-stamped room. When
  /// the load didn't complete (a storage failure), the write is skipped: the
  /// in-memory view is missing rooms that are still on disk, so rewriting it
  /// would drop them. The just-stamped room then stays read in memory for this
  /// session but does not survive a restart until a later load succeeds and a
  /// subsequent stamp re-persists the blob.
  Future<void> _persist(String serverId, String u, String? userId) async {
    final gen = _generation[serverId] ?? 0;
    try {
      await ensureLoaded(serverId: serverId, userId: userId);
      // Disposed or cleared out from under this write: the in-memory state is
      // already gone, so there is nothing left to persist.
      if (_disposed || gen != (_generation[serverId] ?? 0)) return;
      if (!_loaded.contains((serverId: serverId, userId: u))) {
        _logger.warning(
          'Skipped room read marker persist; blob not loaded (a prior load '
          'failed). The stamp holds in memory but is not yet on disk.',
          attributes: {'serverId': serverId, 'userId': u},
        );
        return;
      }
      final blob = <String, DateTime>{
        for (final e in _markers.value.entries)
          if (e.key.serverId == serverId && e.key.userId == u)
            e.key.roomId: e.value,
      };
      await LobbyReadMarkerStorage.saveServer(
        serverId: serverId,
        userId: userId,
        markers: blob,
      );
    } catch (error, st) {
      _logger.warning(
        'Failed to persist room read markers',
        error: error,
        stackTrace: st,
      );
    }
  }

  /// Drops every user's markers for [serverId] from memory and disk, so a
  /// removed server's rooms don't read as read if it's re-added under the same
  /// id. The disk sweep runs unconditionally: the in-memory view can't see
  /// another user's (or an unloaded) blob that may still be on disk.
  void clearServer(String serverId) {
    // Move the epoch first so any in-flight load/persist for this server sees
    // the change and discards its result (see [_generation]).
    _generation[serverId] = (_generation[serverId] ?? 0) + 1;
    final next = {..._markers.value}
      ..removeWhere((key, _) => key.serverId == serverId);
    // Reassign only on a real change, to avoid a spurious watcher notification.
    if (next.length != _markers.value.length) _markers.value = next;
    _loaded.removeWhere((key) => key.serverId == serverId);
    _loadTasks.removeWhere((key, _) => key.serverId == serverId);
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

  /// Drops [roomId] for every user on [serverId] from memory and disk, so a
  /// disappeared room doesn't read as read if re-created under the same id.
  /// Unlike [clearServer] this does not bump [_generation]: the epoch is
  /// server-wide, so bumping it on a single-room clear would abort in-flight
  /// loads/persists for other rooms on the server and drop their stamps.
  ///
  /// The tradeoff is a narrow, self-healing resurrection window rather than a
  /// hard guarantee. An in-flight [_load] or [_persist] for this server that
  /// captured state before the async disk clear finished can re-add [roomId] to
  /// memory (and a later persist then rewrites it to disk). Closing it does not
  /// need the epoch: the disk-level [LobbyReadMarkerStorage.clearRoom] is the
  /// source of truth, a prune only runs on a non-first fetch (the first seeds
  /// the baseline, so no cold-start path opens the window), the local
  /// SharedPreferences reads a prune races against resolve quickly, and a
  /// re-added marker self-corrects on the next genuine clear.
  void clearRoom(String serverId, String roomId) {
    final next = {..._markers.value}..removeWhere(
        (key, _) => key.serverId == serverId && key.roomId == roomId);
    if (next.length != _markers.value.length) _markers.value = next;
    unawaited(
      LobbyReadMarkerStorage.clearRoom(serverId, roomId)
          .catchError((Object error, StackTrace st) {
        _logger.error(
          'Failed to clear room read markers for removed room',
          error: error,
          stackTrace: st,
          attributes: {'serverId': serverId, 'roomId': roomId},
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
    final raw = prefs.getString(_key(serverId, storageUser(userId)));
    if (raw == null || raw.isEmpty) return null;
    final at = DateTime.tryParse(raw);
    if (at == null) {
      _logger.warning(
        'Discarding corrupt server read marker (unparseable)',
        attributes: {
          'serverId': serverId,
          'userId': storageUser(userId),
        },
      );
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
      _key(serverId, storageUser(userId)),
      at.toUtc().toIso8601String(),
    );
  }

  /// Drops every user's marker for [serverId].
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

  final Set<ServerMarkerKey> _loaded = {};

  /// In-flight loads per `(serverId, userId)`, so concurrent callers await the
  /// same disk read instead of one resolving before the marker is in memory.
  final Map<ServerMarkerKey, Future<void>> _loadTasks = {};

  /// Per-server clear epoch, bumped by [clearServer]; see
  /// [RoomReadMarkers._generation]. Only [_load] needs it here — [markRead]
  /// schedules its write without first awaiting a load (unlike
  /// [RoomReadMarkers._persist]), so a [clearServer] sweep enqueued right after
  /// it is ordered behind the write and wins.
  final Map<String, int> _generation = {};

  bool _disposed = false;

  /// The current markers, for a non-reactive read.
  Map<ServerMarkerKey, DateTime> get value => _markers.value;

  /// Loads the `(serverId, userId)` marker once, merging it *under* any stamp
  /// already in-memory. Concurrent calls await the same in-flight load; a failed
  /// load leaves the key unloaded so a later mount retries.
  Future<void> ensureLoaded({
    required String serverId,
    required String? userId,
  }) {
    final key = (serverId: serverId, userId: storageUser(userId));
    if (_loaded.contains(key)) return Future<void>.value();
    return _loadTasks[key] ??= _load(serverId, userId, key);
  }

  Future<void> _load(
      String serverId, String? userId, ServerMarkerKey key) async {
    final gen = _generation[serverId] ?? 0;
    try {
      final at = await ServerReadMarkerStorage.loadServer(
          serverId: serverId, userId: userId);
      // A clear (or dispose) landed while this load was in flight; its marker
      // was swept, so committing it now would resurrect the cleared floor.
      if (_disposed || gen != (_generation[serverId] ?? 0)) return;
      if (at != null && !_markers.value.containsKey(key)) {
        _markers.value = {..._markers.value, key: at};
      }
      _loaded.add(key);
    } catch (error, st) {
      _logger.warning(
        'Failed to load server read marker',
        error: error,
        stackTrace: st,
      );
    } finally {
      // Only clear our own task slot (see [RoomReadMarkers._load]).
      if (gen == (_generation[serverId] ?? 0)) _loadTasks.remove(key);
    }
  }

  /// Stamps [serverId] read as of [at] for [userId] and persists. [at] is
  /// normalized to UTC (see [RoomReadMarkers.markRead]). A null [userId]
  /// resolves to the [unauthenticatedStorageUser] bucket.
  void markRead({
    required String serverId,
    required String? userId,
    required DateTime at,
  }) {
    final u = storageUser(userId);
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
    // Move the epoch first so any in-flight load for this server discards its
    // result (see [_generation]).
    _generation[serverId] = (_generation[serverId] ?? 0) + 1;
    final next = {..._markers.value}
      ..removeWhere((key, _) => key.serverId == serverId);
    // Reassign only on a real change, to avoid a spurious watcher notification.
    if (next.length != _markers.value.length) _markers.value = next;
    _loaded.removeWhere((key) => key.serverId == serverId);
    _loadTasks.removeWhere((key, _) => key.serverId == serverId);
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
