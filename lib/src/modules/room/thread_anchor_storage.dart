import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../core/keyed_storage.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.thread_anchor_storage');

/// Persists per-thread "last read message id" so the room can draw a
/// "New messages" divider at the first unread message.
///
/// The topological twin of [ThreadReadMarkerStorage]: that store keeps a
/// timestamp for the unread dot (computed before history loads); this one keeps a
/// message id for the in-thread line (computed after history loads). Separate
/// stores because the two values have different mutation lifecycles.
///
/// Backed by `shared_preferences`, grained to one blob per `(serverId, userId,
/// roomId)` — the room screen reads one room at a time. The value is a JSON
/// object `{threadId: messageId}`. Keyed via the shared codec so component
/// separators are unambiguous.
abstract final class ThreadAnchorStorage {
  static const _prefix = 'soliplex_thread_anchor';

  static String _key(String serverId, String userId, String roomId) =>
      encodeKey(_prefix, [serverId, userId, roomId]);

  /// The anchors (threadId → last-read message id) for one room and user, or
  /// empty when nothing is stored. A null [userId] (a server requiring no
  /// sign-in) resolves to the shared [unauthenticatedStorageUser] bucket.
  static Future<Map<String, String>> loadRoom({
    required String serverId,
    required String? userId,
    required String roomId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(
        _key(serverId, userId ?? unauthenticatedStorageUser, roomId));
    if (raw == null || raw.isEmpty) return {};

    final result = <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _logger
            .warning('Discarding corrupt thread anchors (not a JSON object)');
        return {};
      }
      var skipped = 0;
      decoded.forEach((key, value) {
        if (key is! String || value is! String) {
          skipped++;
          return;
        }
        result[key] = value;
      });
      if (skipped > 0 && result.isEmpty) {
        // Every entry dropped on a non-empty payload is a systemic
        // serialization break, not one stale row, and it silently resets this
        // room's dividers. Surface it loudly.
        _logger.error('Discarding all $skipped thread anchors; none parsed');
      } else if (skipped > 0) {
        _logger.warning('Skipped $skipped malformed thread anchor(s)');
      }
    } on FormatException catch (e, st) {
      _logger.warning('Discarding corrupt thread anchors',
          error: e, stackTrace: st);
      return {};
    }
    return result;
  }

  /// Persists [anchors] (threadId → message id) as the whole blob for the room. A
  /// null [userId] (a server requiring no sign-in) resolves to the shared
  /// [unauthenticatedStorageUser] bucket.
  static Future<void> saveRoom({
    required String serverId,
    required String? userId,
    required String roomId,
    required Map<String, String> anchors,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key(serverId, userId ?? unauthenticatedStorageUser, roomId),
        jsonEncode(anchors));
  }

  /// Drops every user's anchors for [serverId] (keyed format). Only keyed entries
  /// are removed; any pre-keyed entry under the old key name is left untouched.
  static Future<void> clearServer(String serverId) async {
    final prefs = await SharedPreferences.getInstance();
    final sweep = serverKeyPrefix(_prefix, serverId);
    for (final k
        in prefs.getKeys().where((k) => k.startsWith(sweep)).toList()) {
      await prefs.remove(k);
    }
  }

  /// Drops every user's anchors for [roomId] on [serverId].
  static Future<void> clearRoom(String serverId, String roomId) async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in _roomKeys(prefs, serverId, roomId)) {
      await prefs.remove(k);
    }
  }

  /// Removes [threadId]'s anchor from every user's blob for [roomId] on
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
