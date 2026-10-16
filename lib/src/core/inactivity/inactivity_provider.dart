import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'inactivity_config.dart';
import 'inactivity_monitor.dart';
import 'inactivity_sessions.dart';

/// Holds the active [InactivityConfig].
///
/// Overridden by [SoliplexShell] with the value from [ShellConfig.inactivity].
final inactivityConfigProvider = Provider<InactivityConfig>(
  (_) => throw UnimplementedError('must be overridden by SoliplexShell'),
);

/// The [InactivitySessions] the monitor watches, or `null` when no module
/// supplies one. The auth module overrides it.
final inactivitySessionsProvider = Provider<InactivitySessions?>((_) => null);

/// The shell-scoped [InactivityMonitor], or `null` when nothing supplies
/// [inactivitySessionsProvider].
///
/// Returning nullable keeps the library bootable by consumers that don't
/// include the auth module: inactivity logout simply stays disabled instead
/// of crashing the shell.
final inactivityMonitorProvider = Provider<InactivityMonitor?>((ref) {
  final sessions = ref.watch(inactivitySessionsProvider);
  if (sessions == null) return null;
  final monitor = InactivityMonitor(
    sessions: sessions,
    config: ref.watch(inactivityConfigProvider),
  );
  ref.onDispose(monitor.dispose);
  return monitor;
});
