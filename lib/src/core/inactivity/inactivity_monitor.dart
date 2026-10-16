import 'dart:async';

import 'package:clock/clock.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'inactivity_config.dart';
import 'inactivity_sessions.dart';

/// Tracks user activity and drives the "are you still there?" prompt.
///
/// The monitor watches [InactivitySessions.hasActiveSession] and arms a
/// warning timer whenever at least one session is active. UI code calls
/// [bumpActivity] in response to pointer and keyboard events; if no
/// activity arrives within [InactivityConfig.warningDuration], the
/// warning is shown and a grace timer starts. The grace timer signs
/// every active session out locally when it fires.
///
/// All reactive state is exposed via signals so the shell can drive the
/// dialog without rebuilding the whole tree.
class InactivityMonitor {
  InactivityMonitor({
    required InactivitySessions sessions,
    required InactivityConfig config,
  })  : _sessions = sessions,
        _config = config {
    assert(
      config.warningDuration >= Duration.zero &&
          config.graceDuration >= Duration.zero,
      'InactivityConfig durations must be non-negative '
      '(warning=${config.warningDuration}, grace=${config.graceDuration}).',
    );
    assert(
      (config.warningDuration == Duration.zero) ==
          (config.graceDuration == Duration.zero),
      'InactivityConfig must enable both durations or neither — a single '
      'zero silently disables inactivity logout '
      '(warning=${config.warningDuration}, grace=${config.graceDuration}).',
    );
    if (!_config.isEnabled) return;
    _activeSubscription =
        _sessions.hasActiveSession.subscribe(_onActiveChanged);
  }

  final InactivitySessions _sessions;
  final InactivityConfig _config;
  void Function()? _activeSubscription;

  Timer? _warningTimer;
  Timer? _graceTimer;

  final Signal<bool> _warningVisible = Signal<bool>(false);
  ReadonlySignal<bool> get warningVisible => _warningVisible;

  final Signal<DateTime?> _graceDeadline = Signal<DateTime?>(null);
  ReadonlySignal<DateTime?> get graceDeadline => _graceDeadline;

  /// Resets the warning timer in response to a user interaction.
  ///
  /// No-op while the warning dialog is showing — once the prompt is up,
  /// only an explicit choice (extend or sign out) should resolve it.
  void bumpActivity() {
    if (!_config.isEnabled) return;
    if (_warningVisible.value) return;
    if (!_sessions.hasActiveSession.value) return;
    _armWarningTimer();
  }

  /// "Stay signed in" — dismiss the dialog and restart the warning
  /// timer from zero.
  void extendSession() {
    if (!_warningVisible.value) return;
    _clearGrace();
    _warningVisible.value = false;
    _armWarningTimer();
  }

  /// "Sign out now" — equivalent to letting the grace timer fire.
  void logoutNow() {
    assert(
      _warningVisible.value,
      'logoutNow is only expected while the warning dialog is showing.',
    );
    _performLogout();
  }

  void dispose() {
    _activeSubscription?.call();
    _activeSubscription = null;
    _cancelAllTimers();
  }

  void _onActiveChanged(bool hasActive) {
    if (hasActive) {
      if (_warningTimer == null && !_warningVisible.value) {
        _armWarningTimer();
      }
    } else {
      _cancelAllTimers();
      _clearGrace();
      _warningVisible.value = false;
    }
  }

  void _armWarningTimer() {
    _warningTimer?.cancel();
    _warningTimer = Timer(_config.warningDuration, _onWarningFired);
  }

  void _onWarningFired() {
    _warningTimer = null;
    _warningVisible.value = true;
    _graceDeadline.value = clock.now().add(_config.graceDuration);
    _graceTimer = Timer(_config.graceDuration, _performLogout);
  }

  void _performLogout() {
    _sessions.signOutForInactivity();
    // The hasActiveSession subscription handles dialog dismiss and timer
    // cleanup when the last session flips to NoSession.
  }

  void _cancelAllTimers() {
    _warningTimer?.cancel();
    _graceTimer?.cancel();
    _warningTimer = null;
    _graceTimer = null;
  }

  /// Clears the grace state — the grace timer and its deadline always
  /// move together, so they have a single reset point.
  void _clearGrace() {
    _graceTimer?.cancel();
    _graceTimer = null;
    _graceDeadline.value = null;
  }
}
