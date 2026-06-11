import 'dart:developer' as dev;

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
///
/// Backed by `shared_preferences` (a non-sensitive UI preference used only to
/// prefill the URL field on the empty home screen).
///
/// [load] propagates failures so its caller can fall back to
/// [platformDefaultBackendUrl]; [save] is best-effort and never throws,
/// because its callers sit on a connect-success path where a failed write must
/// not derail the flow.
abstract final class DefaultBackendUrlStorage {
  static const _key = 'backend_base_url';

  static Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_key);
    if (url == null || url.isEmpty) return null;
    return url;
  }

  /// Persists [url] as the last-connected backend.
  ///
  /// Best-effort: a storage failure is logged and swallowed rather than
  /// thrown (see the class doc), so it can't bounce a successful connect to
  /// an error state. A missed write just falls back to the platform default
  /// on the next launch.
  static Future<void> save(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, url);
    } catch (e, st) {
      dev.log(
        'Failed to persist default backend url ($url)',
        error: e,
        stackTrace: st,
        level: 1000,
      );
    }
  }
}
