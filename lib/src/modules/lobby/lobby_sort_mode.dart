import 'package:shared_preferences/shared_preferences.dart';

/// How the lobby orders a server's rooms.
///
/// [recentActivity] sorts by the most recently *created* thread in each room
/// (the only recency signal the backend exposes today — there is no
/// last-access field). Rooms with no threads sort last.
///
/// [unreadFirst] groups rooms into an Unread section above a Read section,
/// each ordered by recent activity. It groups by *attention status* rather
/// than *time*; it is mutually exclusive with [recentActivity].
enum LobbySortMode { none, recentActivity, unreadFirst }

/// Persists the user's preferred [LobbySortMode] across launches.
///
/// Backed by `shared_preferences` (the choice is a non-sensitive UI
/// preference). An unset or unrecognized value falls back to
/// [LobbySortMode.none].
abstract final class LobbySortModeStorage {
  static const _key = 'soliplex_lobby_sort_mode';

  static Future<LobbySortMode> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    return LobbySortMode.values.where((mode) => mode.name == raw).firstOrNull ??
        LobbySortMode.none;
  }

  static Future<void> save(LobbySortMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}
