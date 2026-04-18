import 'package:shared_preferences/shared_preferences.dart';

/// Resolves the default backend URL using platform logic.
///
/// On native (or web served from localhost), returns [configUrl].
/// On web served from a remote host, returns the page origin.
String platformDefaultBackendUrl({
  String configUrl = 'http://localhost:8000',
  bool isWeb = false,
  Uri? webOrigin,
}) {
  if (!isWeb || webOrigin == null) return configUrl;
  final host = webOrigin.host;
  if (host == 'localhost' || host == '127.0.0.1') return configUrl;
  return webOrigin.origin;
}

/// Persists and retrieves the user's last-connected backend URL.
abstract final class DefaultBackendUrlStorage {
  static const _key = 'backend_base_url';

  static Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_key);
    if (url == null || url.isEmpty) return null;
    return url;
  }

  static Future<void> save(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, url);
  }
}
