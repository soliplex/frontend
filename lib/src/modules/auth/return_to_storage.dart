import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.return_to_storage');

/// Per-screen snapshot store for state that needs to survive an
/// auth-failure round-trip (composer drafts, quiz progress).
///
/// Backed by `shared_preferences` rather than `flutter_secure_storage`
/// because none of the persisted state is sensitive — tokens go
/// through the secure store.
///
/// Entries expire after 24 hours so drafts survive multi-minute OIDC
/// roundtrips with retries while still bounding staleness.
abstract final class ReturnToStorage {
  static const _prefix = 'soliplex_return_to';

  /// Entries older than this are treated as missing and lazily cleared
  /// on the next read.
  static const maxAge = Duration(hours: 24);

  static String _composerKey(String serverId, String roomId) =>
      '$_prefix:composer:$serverId:$roomId';

  /// Stores the unsent composer text for a `(serverId, roomId)` pair.
  ///
  /// Empty / whitespace-only text is treated as "no draft" and clears
  /// any existing entry — there's nothing meaningful to restore.
  static Future<void> saveComposer({
    required String serverId,
    required String roomId,
    required String unsentText,
    DateTime? now,
  }) async {
    final trimmed = unsentText.trim();
    if (trimmed.isEmpty) {
      await clearComposer(serverId: serverId, roomId: roomId);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final entry = {
      'unsentText': unsentText,
      'createdAt': (now ?? DateTime.timestamp()).toUtc().toIso8601String(),
    };
    await prefs.setString(_composerKey(serverId, roomId), jsonEncode(entry));
  }

  /// Returns the previously persisted composer text for the pair, or
  /// `null` when missing, expired, or corrupted. Expired or corrupted
  /// entries are removed from storage as a side effect.
  static Future<String?> loadComposer({
    required String serverId,
    required String roomId,
    DateTime? now,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_composerKey(serverId, roomId));
    if (raw == null) return null;

    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final createdAt = DateTime.parse(json['createdAt'] as String).toUtc();
      final currentTime = now ?? DateTime.timestamp();
      if (currentTime.difference(createdAt) > maxAge) {
        await clearComposer(serverId: serverId, roomId: roomId);
        return null;
      }
      return json['unsentText'] as String?;
    } catch (e, st) {
      _logger.warning(
        'Corrupted composer entry; clearing',
        error: e,
        stackTrace: st,
      );
      await clearComposer(serverId: serverId, roomId: roomId);
      return null;
    }
  }

  static Future<void> clearComposer({
    required String serverId,
    required String roomId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_composerKey(serverId, roomId));
  }

  /// Removes every composer draft belonging to [serverId], so a removed
  /// server's unsent text can't resurface in a re-added room.
  ///
  /// Matches by key prefix. This is exact for the common case, but the key
  /// joins [serverId] and roomId with an unescaped `:`, and a server id is a
  /// `Uri.origin` (which omits the default port). So a portless origin is a
  /// prefix of the same host with an explicit port — `clearServer` for
  /// `https://foo.com` also sweeps `https://foo.com:8443`'s drafts. Bounded and
  /// rare (both servers on one host, one with an unsent draft); the unambiguous
  /// fix is the keyed-store migration tracked in issue #393.
  static Future<void> clearServer(String serverId) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = '$_prefix:composer:$serverId:';
    final keys = prefs.getKeys().where((key) => key.startsWith(prefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}
