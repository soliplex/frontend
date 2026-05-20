import 'dart:convert';
import 'dart:developer' as dev;

import 'package:shared_preferences/shared_preferences.dart';

/// Per-screen snapshot store for state that needs to survive an
/// auth-failure round-trip (composer drafts, quiz progress).
///
/// Backed by `shared_preferences` rather than `flutter_secure_storage`
/// because none of the persisted state is sensitive — tokens go
/// through the secure store.
///
/// Entries expire after 24 hours. Drafts are user content, so the TTL
/// is generous: a 5-minute TTL would silently delete a composer draft
/// if the user took six minutes to sign back in, which is hostile.
/// 24 hours bounds the staleness window without surprising the user.
abstract final class ReturnToStorage {
  /// Prefix for every key written by this store. Lets us namespace
  /// cleanly and grep for it during debugging.
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
      dev.log(
        'ReturnToStorage: corrupted composer entry; clearing',
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
}
