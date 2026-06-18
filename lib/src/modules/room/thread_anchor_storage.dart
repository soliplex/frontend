import 'dart:convert';
import 'dart:developer' as dev;

import 'package:shared_preferences/shared_preferences.dart';

import 'thread_read_markers.dart' show ThreadActivityKey;

/// Persists per-thread "last read message id" so the room can draw a
/// "New messages" divider at the first unread message.
///
/// The topological twin of [ThreadReadMarkerStorage]: that store keeps a
/// timestamp for the unread dot (computed before history loads); this one
/// keeps a message id for the in-thread line (computed after history loads).
/// Separate stores because the two values have different mutation lifecycles.
/// Device-local; stored as a JSON array of `{s, r, th, id}` objects so the
/// ids needn't be escaped into a composite key.
abstract final class ThreadAnchorStorage {
  static const _key = 'soliplex_thread_unread_anchors';

  static Future<Map<ThreadActivityKey, String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};

    final result = <ThreadActivityKey, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        dev.log(
          'Discarding corrupt thread anchors (not a JSON array)',
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
        final id = entry['id'];
        if (s is! String || r is! String || th is! String || id is! String) {
          skipped++;
          continue;
        }
        result[(serverId: s, roomId: r, threadId: th)] = id;
      }
      if (skipped > 0 && result.isEmpty) {
        dev.log('Discarding all $skipped thread anchors; none parsed',
            level: 1000);
      } else if (skipped > 0) {
        dev.log('Skipped $skipped malformed thread anchor(s)', level: 900);
      }
    } on FormatException catch (e, st) {
      dev.log(
        'Discarding corrupt thread anchors',
        error: e,
        stackTrace: st,
        level: 900,
      );
      return {};
    }
    return result;
  }

  static Future<void> save(Map<ThreadActivityKey, String> anchors) async {
    final prefs = await SharedPreferences.getInstance();
    final list = [
      for (final entry in anchors.entries)
        {
          's': entry.key.serverId,
          'r': entry.key.roomId,
          'th': entry.key.threadId,
          'id': entry.value,
        },
    ];
    await prefs.setString(_key, jsonEncode(list));
  }
}
