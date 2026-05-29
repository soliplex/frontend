import 'package:shared_preferences/shared_preferences.dart';

/// How the lobby lays out each server's rooms.
enum LobbyViewMode { list, grid }

/// Persists the user's preferred [LobbyViewMode] across launches.
///
/// Backed by `shared_preferences` (the choice is a non-sensitive UI
/// preference). An unset or unrecognized value falls back to
/// [LobbyViewMode.list].
abstract final class LobbyViewModeStorage {
  static const _key = 'soliplex_lobby_view_mode';

  static Future<LobbyViewMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    return LobbyViewMode.values.where((mode) => mode.name == raw).firstOrNull ??
        LobbyViewMode.list;
  }

  static Future<void> save(LobbyViewMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}
