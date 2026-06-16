import 'dart:convert';
import 'dart:developer' as dev;

import 'package:shared_preferences/shared_preferences.dart';

import 'lobby_state.dart' show RoomActivityKey;

/// Persists per-room "last seen" timestamps so the lobby can mark rooms with
/// newer activity as unread.
///
/// This is a deliberately simple, *client-side* read model: a room is unread
/// when its last-message time is newer than the moment the user last opened
/// it on this device. There is no server-side read state and no count — just
/// a boolean affordance. Read markers are therefore per-device.
///
/// Backed by `shared_preferences` (non-sensitive UI state). Stored as a JSON
/// array of `{s, r, t}` objects (server id, room id, ISO-8601 UTC instant) so
/// ids needn't be escaped into a composite key.
abstract final class LobbyReadMarkerStorage {
  static const _key = 'soliplex_lobby_read_markers';

  static Future<Map<RoomActivityKey, DateTime>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};

    final result = <RoomActivityKey, DateTime>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        dev.log(
          'Discarding corrupt lobby read markers (not a JSON array)',
          level: 900,
        );
        return {};
      }
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final s = entry['s'];
        final r = entry['r'];
        final t = entry['t'];
        if (s is! String || r is! String || t is! String) continue;
        final at = DateTime.tryParse(t);
        if (at == null) continue;
        result[(serverId: s, roomId: r)] = at.toUtc();
      }
    } on FormatException catch (e, st) {
      // Corrupt payload: start fresh rather than wedging the lobby.
      dev.log(
        'Discarding corrupt lobby read markers',
        error: e,
        stackTrace: st,
        level: 900,
      );
      return {};
    }
    return result;
  }

  static Future<void> save(Map<RoomActivityKey, DateTime> markers) async {
    final prefs = await SharedPreferences.getInstance();
    final list = [
      for (final entry in markers.entries)
        {
          's': entry.key.serverId,
          'r': entry.key.roomId,
          't': entry.value.toUtc().toIso8601String(),
        },
    ];
    await prefs.setString(_key, jsonEncode(list));
  }
}
