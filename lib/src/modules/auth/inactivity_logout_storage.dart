import 'dart:developer' as dev;

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
///
/// Every method degrades gracefully if the storage layer throws: writes
/// and clears become no-ops and reads default to not-marked, each logged
/// at SEVERE. Storage is best-effort here precisely because a thrown
/// `PlatformException` must not wedge the auth flow ([isMarked] runs
/// before sign-in) or mask a completed sign-in as a failure ([clear]
/// runs after it). The two write failures fail safe in opposite
/// directions: a lost [clear] forces a harmless extra `prompt=login` on
/// the next sign-in, while a lost [mark] lets the next sign-in proceed
/// via SSO instead of forcing the intended re-authentication.
class LocalInactivityLogoutFlagStorage implements InactivityLogoutFlagStorage {
  LocalInactivityLogoutFlagStorage({
    Future<SharedPreferences> Function()? prefsFactory,
  }) : _prefsFactory = prefsFactory ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefsFactory;

  static const _prefix = 'soliplex_inactivity_logout_pending_';

  String _key(String serverId) => '$_prefix$serverId';

  @override
  Future<void> mark(String serverId) async {
    try {
      final prefs = await _prefsFactory();
      await prefs.setBool(_key(serverId), true);
    } catch (e, st) {
      dev.log(
        'Failed to persist inactivity-logout flag for $serverId',
        error: e,
        stackTrace: st,
        level: 1000,
      );
    }
  }

  @override
  Future<bool> isMarked(String serverId) async {
    try {
      final prefs = await _prefsFactory();
      return prefs.getBool(_key(serverId)) ?? false;
    } catch (e, st) {
      dev.log(
        'Failed to read inactivity-logout flag for $serverId; '
        'defaulting to not-marked',
        error: e,
        stackTrace: st,
        level: 1000,
      );
      return false;
    }
  }

  @override
  Future<void> clear(String serverId) async {
    try {
      final prefs = await _prefsFactory();
      await prefs.remove(_key(serverId));
    } catch (e, st) {
      dev.log(
        'Failed to clear inactivity-logout flag for $serverId',
        error: e,
        stackTrace: st,
        level: 1000,
      );
    }
  }
}
