import 'package:shared_preferences/shared_preferences.dart';

/// Persists the id of the server the user last viewed in the lobby, so the
/// selection survives launches.
///
/// Backed by `shared_preferences` (a non-sensitive UI preference). Storing
/// `null` clears the preference — the lobby then falls back to the first
/// available server.
abstract final class SelectedServerStorage {
  static const _key = 'soliplex_lobby_selected_server';

  static Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  static Future<void> save(String? serverId) async {
    final prefs = await SharedPreferences.getInstance();
    if (serverId == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, serverId);
    }
  }
}
