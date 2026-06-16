import 'dart:convert';
import 'dart:developer' as dev;

import 'package:shared_preferences/shared_preferences.dart';

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
        dev.log(
          'Discarding corrupt thread read markers (not a JSON array)',
          level: 900,
        );
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
        dev.log(
          'Discarding all $skipped thread read markers; none parsed',
          level: 1000,
        );
      } else if (skipped > 0) {
        dev.log(
          'Skipped $skipped malformed thread read marker(s)',
          level: 900,
        );
      }
    } on FormatException catch (e, st) {
      // Corrupt payload: start fresh rather than wedging the room.
      dev.log(
        'Discarding corrupt thread read markers',
        error: e,
        stackTrace: st,
        level: 900,
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
}
