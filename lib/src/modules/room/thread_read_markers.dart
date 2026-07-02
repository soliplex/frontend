import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.thread_read_markers');

/// Identifies a thread across servers and rooms for the read model. Named
/// fields (rather than a positional tuple) so the three ids can't be
/// transposed at a lookup or insertion site.
typedef ThreadActivityKey = ({String serverId, String roomId, String threadId});

/// Persists per-thread "last seen" timestamps so the room can mark threads
/// with newer activity as unread.
///
/// The thread-level twin of the lobby's room read model: a thread is unread
/// when its last-message time is newer than the moment the user last opened
/// it on this device. There is no server-side read state and no count — just
/// a boolean affordance. Read markers are therefore per-device.
///
/// Backed by `shared_preferences` (non-sensitive UI state). Stored as a JSON
/// array of `{s, r, th, t}` objects (server id, room id, thread id, ISO-8601
/// UTC instant) so ids needn't be escaped into a composite key.
abstract final class ThreadReadMarkerStorage {
  static const _key = 'soliplex_thread_read_markers';

  static Future<Map<ThreadActivityKey, DateTime>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};

    final result = <ThreadActivityKey, DateTime>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _logger.warning(
            'Discarding corrupt thread read markers (not a JSON array)');
        return {};
      }
      var skipped = 0;
      for (final entry in decoded) {
        if (entry is! Map) {
          skipped++;
          continue;
        }
        final s = entry['s'];
        final r = entry['r'];
        final th = entry['th'];
        final t = entry['t'];
        if (s is! String || r is! String || th is! String || t is! String) {
          skipped++;
          continue;
        }
        final at = DateTime.tryParse(t);
        if (at == null) {
          skipped++;
          continue;
        }
        result[(serverId: s, roomId: r, threadId: th)] = at.toUtc();
      }
      if (skipped > 0 && result.isEmpty) {
        // Every row dropped on a non-empty payload is a systemic serialization
        // break, not one stale row, and it silently resets the read model
        // (every thread flips to unread). Surface it loudly.
        _logger
            .error('Discarding all $skipped thread read markers; none parsed');
      } else if (skipped > 0) {
        _logger.warning('Skipped $skipped malformed thread read marker(s)');
      }
    } on FormatException catch (e, st) {
      // Corrupt payload: start fresh rather than wedging the room.
      _logger.warning(
        'Discarding corrupt thread read markers',
        error: e,
        stackTrace: st,
      );
      return {};
    }
    return result;
  }

  static Future<void> save(Map<ThreadActivityKey, DateTime> markers) async {
    final prefs = await SharedPreferences.getInstance();
    final list = [
      for (final entry in markers.entries)
        {
          's': entry.key.serverId,
          'r': entry.key.roomId,
          'th': entry.key.threadId,
          't': entry.value.toUtc().toIso8601String(),
        },
    ];
    await prefs.setString(_key, jsonEncode(list));
  }

  /// Drops every thread marker for [serverId], so a removed server's threads
  /// don't read as read if the server is re-added under the same id. No-op (and
  /// no write) when the server has no markers.
  ///
  /// Fire-and-forget with no retry: unlike the signal-backed room/server
  /// stores, this has no in-memory owner to re-save a corrected map, so a
  /// failed [save] leaves stale thread floors on disk (a re-added same-id
  /// server reads as already-read). Accepted because a re-add after a write
  /// failure is rare and the caller logs the failure at error level. A live
  /// RoomScreen's marker flush, which persists its full cross-server map, can
  /// likewise overwrite this clear — reachable only if lobby and room are ever
  /// mounted at once, which the current navigation never does.
  static Future<void> clearServer(String serverId) async {
    final markers = await load();
    final next = {...markers}
      ..removeWhere((key, _) => key.serverId == serverId);
    if (next.length == markers.length) return;
    await save(next);
  }
}
