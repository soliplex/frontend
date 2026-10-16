import 'package:soliplex_agent/soliplex_agent.dart' show ReadonlySignal;

/// What `InactivityMonitor` needs from whoever owns the signed-in sessions.
///
/// Defined here and implemented by the auth module, so core depends on no
/// module (ADR-005). The auth module supplies it through
/// `inactivitySessionsProvider`.
abstract interface class InactivitySessions {
  /// Whether at least one session is signed in. The monitor arms its warning
  /// timer while this is true and stands down when it turns false.
  ReadonlySignal<bool> get hasActiveSession;

  /// Signs every active session out locally because the user went idle.
  ///
  /// Records the inactivity logout per server before signing out, so the
  /// next connect forces a fresh login rather than reusing a silent IdP
  /// session.
  void signOutForInactivity();
}
