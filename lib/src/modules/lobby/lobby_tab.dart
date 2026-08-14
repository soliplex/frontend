import 'package:shared_preferences/shared_preferences.dart';

/// Which section of the selected server the lobby is showing.
///
/// The lobby used to be rooms and nothing else; threads aggregates every
/// room's threads into one list so a thread can be found without first
/// recalling which room it lives in.
enum LobbyTab {
  /// The server's rooms, as a list or grid.
  rooms,

  /// Every thread the user has in the server, grouped by room.
  threads,
}

/// Persists the user's last [LobbyTab] across launches.
///
/// Backed by `shared_preferences` (the choice is a non-sensitive UI
/// preference). An unset or unrecognized value falls back to
/// [LobbyTab.rooms] — the lobby's historical behaviour, and the right
/// landing place for anyone who has not opted into the threads view.
abstract final class LobbyTabStorage {
  static const _key = 'soliplex_lobby_tab';

  static Future<LobbyTab> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    return LobbyTab.values.where((tab) => tab.name == raw).firstOrNull ??
        LobbyTab.rooms;
  }

  static Future<void> save(LobbyTab tab) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, tab.name);
  }
}
