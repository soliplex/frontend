import 'package:shared_preferences/shared_preferences.dart';

/// Per-server flag recording that the most recent logout was triggered by
/// the inactivity monitor.
///
/// On the next sign-in for that server, [ConnectFlow] reads the flag via
/// [isMarked] and forwards `prompt=login` to the IdP, forcing a
/// credential challenge even when the IdP's SSO cookie is still valid.
/// The flag is cleared via [clear] only after a successful sign-in —
/// not on read — so a cancelled or failed IdP challenge does not
/// silently downgrade the next attempt to SSO.
abstract class InactivityLogoutFlagStorage {
  /// Records that this server's last logout was due to inactivity.
  Future<void> mark(String serverId);

  /// Reads the flag without mutating it. Returns true if the next
  /// sign-in for this server should include `prompt=login`.
  Future<bool> isMarked(String serverId);

  /// Clears the flag. Call only after the user has completed a
  /// credential-challenged sign-in — leaving the flag in place across
  /// cancelled or failed attempts keeps the security closure intact on
  /// retry.
  Future<void> clear(String serverId);
}

/// SharedPreferences-backed implementation. The flag is not sensitive —
/// it carries no token material — so it lives in shared_preferences
/// rather than secure storage.
class SharedPrefsInactivityLogoutFlagStorage
    implements InactivityLogoutFlagStorage {
  static const _prefix = 'soliplex_inactivity_logout_pending_';

  String _key(String serverId) => '$_prefix$serverId';

  @override
  Future<void> mark(String serverId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(serverId), true);
  }

  @override
  Future<bool> isMarked(String serverId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(serverId)) ?? false;
  }

  @override
  Future<void> clear(String serverId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(serverId));
  }
}
