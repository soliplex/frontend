import 'dart:developer' as dev;

import 'package:shared_preferences/shared_preferences.dart';

/// Persists the id of the active server so the lobby can restore the
/// selection across launches.
///
/// Backed by `shared_preferences` (a non-sensitive UI preference). Storing
/// `null` clears the preference — the lobby then falls back to the first
/// available server.
///
/// [load] propagates failures so its caller can choose a fallback; [save] is
/// best-effort and never throws, because its callers sit on a success path
/// where a failed write must not derail the flow.
abstract final class SelectedServerStorage {
  static const _key = 'soliplex_lobby_selected_server';

  static Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  /// Persists [serverId], or clears the preference when `null`.
  ///
  /// Best-effort: a storage failure is logged and swallowed rather than
  /// thrown (see the class doc), so it can't bounce a successful sign-in to
  /// an error state. A missed write just falls back to the default selection
  /// on the next launch.
  static Future<void> save(String? serverId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (serverId == null) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, serverId);
      }
    } catch (e, st) {
      dev.log(
        'Failed to persist selected server ($serverId)',
        error: e,
        stackTrace: st,
        level: 1000,
      );
    }
  }
}
