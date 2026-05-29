import 'package:shared_preferences/shared_preferences.dart';

/// Persists the set of server IDs whose rooms are hidden from the lobby
/// content, so the choice survives launches.
///
/// Backed by `shared_preferences` (a non-sensitive UI preference). The
/// hidden state is per-server visibility only — it does not sign the user
/// out or remove the server.
abstract final class HiddenServersStorage {
  static const _key = 'soliplex_lobby_hidden_servers';

  static Future<Set<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key)?.toSet() ?? <String>{};
  }

  static Future<void> save(Set<String> serverIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, serverIds.toList());
  }
}
