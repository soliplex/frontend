import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'thread_read_markers.dart' show ThreadActivityKey;

final Logger _logger =
    LogManager.instance.getLogger('soliplex.thread_anchor_storage');

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

  // Row field names, shared by load and save so the read/write contract can't
  // drift: a typo in one half alone would silently drop every row.
  static const _fieldServer = 's';
  static const _fieldRoom = 'r';
  static const _fieldThread = 'th';
  static const _fieldId = 'id';

  /// Returns the stored anchors, dropping corrupt rows. Throws on an
  /// underlying storage I/O failure; callers must handle it.
  static Future<Map<ThreadActivityKey, String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};

    final result = <ThreadActivityKey, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _logger.warning('Discarding corrupt thread anchors (not a JSON array)');
        return {};
      }
      var skipped = 0;
      for (final entry in decoded) {
        if (entry is! Map) {
          skipped++;
          continue;
        }
        final s = entry[_fieldServer];
        final r = entry[_fieldRoom];
        final th = entry[_fieldThread];
        final id = entry[_fieldId];
        if (s is! String || r is! String || th is! String || id is! String) {
          skipped++;
          continue;
        }
        result[(serverId: s, roomId: r, threadId: th)] = id;
      }
      // Every row dropped on a non-empty payload is a systemic serialization
      // break, not one stale row, and it silently resets the read model. Surface
      // it loudly.
      if (skipped > 0 && result.isEmpty) {
        _logger.error('Discarding all $skipped thread anchors; none parsed');
      } else if (skipped > 0) {
        _logger.warning('Skipped $skipped malformed thread anchor(s)');
      }
    } on FormatException catch (e, st) {
      // Corrupt payload: start fresh rather than wedging the room.
      _logger.warning(
        'Discarding corrupt thread anchors',
        error: e,
        stackTrace: st,
      );
      return {};
    }
    return result;
  }

  /// Throws on an underlying storage I/O failure; callers must handle it.
  static Future<void> save(Map<ThreadActivityKey, String> anchors) async {
    final prefs = await SharedPreferences.getInstance();
    final list = [
      for (final entry in anchors.entries)
        {
          _fieldServer: entry.key.serverId,
          _fieldRoom: entry.key.roomId,
          _fieldThread: entry.key.threadId,
          _fieldId: entry.value,
        },
    ];
    await prefs.setString(_key, jsonEncode(list));
  }

  /// Drops every anchor for [serverId], so a removed server's threads don't
  /// restore a stale "New messages" divider if the server is re-added under the
  /// same id. No-op (and no write) when the server has no anchors.
  ///
  /// Propagates I/O failures from [load]/[save] to the caller (like the thread
  /// read-marker store); callers run it fire-and-forget and log. A failed [save]
  /// leaves stale anchors on disk — accepted because an anchor only positions a
  /// divider (it never floors unread state), so a surviving stale anchor is a
  /// cosmetic misplacement, not a correctness break.
  static Future<void> clearServer(String serverId) async {
    final anchors = await load();
    final next = {...anchors}
      ..removeWhere((key, _) => key.serverId == serverId);
    if (next.length == anchors.length) return;
    await save(next);
  }
}
