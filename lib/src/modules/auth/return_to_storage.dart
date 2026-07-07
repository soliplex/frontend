import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../core/keyed_storage.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.return_to_storage');

/// Per-user composer-draft store, keyed by (serverId, userId, roomId).
///
/// Backed by `shared_preferences` rather than `flutter_secure_storage`
/// because none of the persisted state is sensitive — tokens go
/// through the secure store.
///
/// Entries expire after [maxAge] so drafts survive multi-minute OIDC
/// roundtrips with retries while still bounding staleness.
abstract final class ReturnToStorage {
  static const _prefix = 'soliplex_return_to:composer';

  /// Entries older than this are treated as missing and lazily cleared
  /// on the next read.
  static const maxAge = Duration(hours: 24);

  static String _key(String serverId, String userId, String roomId) =>
      encodeKey(_prefix, [serverId, userId, roomId]);

  /// Stores the unsent composer text for a `(serverId, userId, roomId)`
  /// triple. A `null` [userId] means the user can't be attributed (signed
  /// out) and is a no-op — there's no scope to save under.
  ///
  /// Empty / whitespace-only text is treated as "no draft" and clears
  /// any existing entry — there's nothing meaningful to restore.
  static Future<void> saveComposer({
    required String serverId,
    required String? userId,
    required String roomId,
    required String unsentText,
    DateTime? now,
  }) async {
    if (userId == null) return;
    final trimmed = unsentText.trim();
    if (trimmed.isEmpty) {
      await clearComposer(serverId: serverId, userId: userId, roomId: roomId);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final entry = {
      'unsentText': unsentText,
      'createdAt': (now ?? DateTime.timestamp()).toUtc().toIso8601String(),
    };
    await prefs.setString(_key(serverId, userId, roomId), jsonEncode(entry));
  }

  /// Returns the previously persisted composer text for the triple, or
  /// `null` when missing, expired, corrupted, or [userId] is `null`.
  /// Expired or corrupted entries are removed from storage as a side
  /// effect.
  static Future<String?> loadComposer({
    required String serverId,
    required String? userId,
    required String roomId,
    DateTime? now,
  }) async {
    if (userId == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(serverId, userId, roomId));
    if (raw == null) return null;

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final createdAt = DateTime.parse(json['createdAt'] as String).toUtc();
      final currentTime = now ?? DateTime.timestamp();
      if (currentTime.difference(createdAt) > maxAge) {
        await clearComposer(serverId: serverId, userId: userId, roomId: roomId);
        return null;
      }
      return json['unsentText'] as String?;
    } catch (e, st) {
      _logger.warning(
        'Corrupted composer entry; clearing',
        error: e,
        stackTrace: st,
      );
      await clearComposer(serverId: serverId, userId: userId, roomId: roomId);
      return null;
    }
  }

  static Future<void> clearComposer({
    required String serverId,
    required String userId,
    required String roomId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(serverId, userId, roomId));
  }

  /// Removes every user's draft belonging to [serverId], so a removed
  /// server's unsent text can't resurface in a re-added room. Matches the
  /// percent-encoded key format; pre-userId (legacy) raw-key drafts are
  /// abandoned by the one-time launch sweep, not handled here.
  static Future<void> clearServer(String serverId) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = serverKeyPrefix(_prefix, serverId);
    final keys = prefs.getKeys().where((key) => key.startsWith(prefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  /// Removes every user's draft for `(serverId, roomId)`.
  static Future<void> clearRoom(String serverId, String roomId) async {
    final prefs = await SharedPreferences.getInstance();
    final dead = prefs.getKeys().where((key) {
      final components = decodeKey(_prefix, key);
      return components != null &&
          components.length == 3 &&
          components[0] == serverId &&
          components[2] == roomId;
    });
    for (final key in dead) {
      await prefs.remove(key);
    }
  }
}
