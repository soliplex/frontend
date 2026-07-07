import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../core/keyed_storage.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.thread_read_markers');

/// Identifies a thread across servers and rooms for the read model. Named
/// fields (rather than a positional tuple) so the three ids can't be
/// transposed at a lookup or insertion site.
typedef ThreadActivityKey = ({String serverId, String roomId, String threadId});

/// Persists per-thread "last seen" timestamps so the room can mark threads with
/// newer activity as unread.
///
/// The thread-level twin of the lobby's room read model: a thread is unread when
/// its last-message time is newer than the moment the user last opened it on this
/// device. There is no server-side read state and no count — just a boolean
/// affordance, per device and per user.
///
/// Backed by `shared_preferences` (non-sensitive UI state), grained to one blob
/// per `(serverId, userId, roomId)` — the room screen reads one room at a time,
/// so the blob matches the read-unit. The value is a JSON object `{threadId:
/// ISO-8601 UTC instant}`. Keyed via the shared codec so component separators are
/// unambiguous.
abstract final class ThreadReadMarkerStorage {
  static const _prefix = 'soliplex_thread_read_marker';

  static String _key(String serverId, String userId, String roomId) =>
      encodeKey(_prefix, [serverId, userId, roomId]);

  /// The read markers (threadId → last-seen instant) for one room and user, or
  /// empty when [userId] is null (signed out) or nothing is stored.
  static Future<Map<String, DateTime>> loadRoom({
    required String serverId,
    required String? userId,
    required String roomId,
  }) async {
    if (userId == null) return {};
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(serverId, userId, roomId));
    if (raw == null || raw.isEmpty) return {};

    final result = <String, DateTime>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _logger.warning(
            'Discarding corrupt thread read markers (not a JSON object)');
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
      if (skipped > 0 && result.isEmpty) {
        // Every entry dropped on a non-empty payload is a systemic
        // serialization break, not one stale row, and it silently resets this
        // room's read model. Surface it loudly.
        _logger
            .error('Discarding all $skipped thread read markers; none parsed');
      } else if (skipped > 0) {
        _logger.warning('Skipped $skipped malformed thread read marker(s)');
      }
    } on FormatException catch (e, st) {
      _logger.warning('Discarding corrupt thread read markers',
          error: e, stackTrace: st);
      return {};
    }
    return result;
  }

  /// Persists [markers] (threadId → instant) as the whole blob for the room.
  /// No-op when [userId] is null.
  static Future<void> saveRoom({
    required String serverId,
    required String? userId,
    required String roomId,
    required Map<String, DateTime> markers,
  }) async {
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final obj = {
      for (final e in markers.entries) e.key: e.value.toUtc().toIso8601String(),
    };
    await prefs.setString(_key(serverId, userId, roomId), jsonEncode(obj));
  }

  /// Drops every user's thread markers for [serverId] (keyed format). Legacy
  /// pre-keyed markers are swept once by the first-launch migration (PR 6), not
  /// here.
  static Future<void> clearServer(String serverId) async {
    final prefs = await SharedPreferences.getInstance();
    final sweep = serverKeyPrefix(_prefix, serverId);
    for (final k
        in prefs.getKeys().where((k) => k.startsWith(sweep)).toList()) {
      await prefs.remove(k);
    }
  }

  /// Drops every user's thread markers for [roomId] on [serverId].
  static Future<void> clearRoom(String serverId, String roomId) async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in _roomKeys(prefs, serverId, roomId)) {
      await prefs.remove(k);
    }
  }

  /// Removes [threadId]'s marker from every user's blob for [roomId] on
  /// [serverId], leaving sibling threads intact.
  static Future<void> clearThread(
      String serverId, String roomId, String threadId) async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in _roomKeys(prefs, serverId, roomId)) {
      final raw = prefs.getString(k);
      if (raw == null || raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map || !decoded.containsKey(threadId)) continue;
        decoded.remove(threadId);
        await prefs.setString(k, jsonEncode(decoded));
      } on FormatException {
        continue;
      }
    }
  }

  /// Every stored key (any user) for [roomId] on [serverId].
  static List<String> _roomKeys(
          SharedPreferences prefs, String serverId, String roomId) =>
      prefs.getKeys().where((k) {
        final c = decodeKey(_prefix, k);
        return c != null && c.length == 3 && c[0] == serverId && c[2] == roomId;
      }).toList();
}
