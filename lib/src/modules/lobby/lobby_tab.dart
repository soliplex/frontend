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

  /// The server's label catalogue.
  ///
  /// Administrators only — see [visibleLobbyTabs]. Labels are global to
  /// the server, so curating them is not an ordinary user's business,
  /// and there is nothing for a non-administrator to do here.
  labels,
}

/// The tabs to show a user with the given [isAdmin] standing.
///
/// The labels tab is omitted entirely for non-administrators rather than
/// shown read-only. Every control on it is an administrator action, so a
/// read-only version would be a tab of things you cannot do — and the
/// catalogue is still discoverable where it matters, through the
/// `@label` autocomplete in the threads search and the label picker in a
/// thread's properties.
///
/// This is presentation only. Nothing is authorized by it: the server
/// refuses a non-administrator's write whether or not the tab was drawn.
List<LobbyTab> visibleLobbyTabs({required bool isAdmin}) => [
      LobbyTab.rooms,
      LobbyTab.threads,
      if (isAdmin) LobbyTab.labels,
    ];

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
