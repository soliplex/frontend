import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../modules/auth/auth_providers.dart';
import '../../modules/auth/inactivity_logout_storage.dart';
import '../../modules/auth/server_manager.dart';
import 'inactivity_config.dart';
import 'inactivity_monitor.dart';

/// Holds the active [InactivityConfig].
///
/// Overridden by [SoliplexShell] with the value from [ShellConfig.inactivity].
final inactivityConfigProvider = Provider<InactivityConfig>(
  (_) => throw UnimplementedError('must be overridden by SoliplexShell'),
);

/// The shell-scoped [InactivityMonitor], or `null` when the auth-module
/// providers it depends on (`serverManagerProvider`,
/// `inactivityLogoutFlagsProvider`) are not configured.
///
/// Returning nullable keeps the library bootable by consumers that
/// don't include the auth module — inactivity logout simply stays
/// disabled instead of crashing the shell.
final inactivityMonitorProvider = Provider<InactivityMonitor?>((ref) {
  final ServerManager serverManager;
  final InactivityLogoutFlagStorage flags;
  try {
    serverManager = ref.watch(serverManagerProvider);
    flags = ref.watch(inactivityLogoutFlagsProvider);
  } catch (_) {
    // Auth module providers not overridden — keep the shell bootable
    // for consumers that don't include them.
    return null;
  }
  final monitor = InactivityMonitor(
    servers: serverManager.servers,
    config: ref.watch(inactivityConfigProvider),
    inactivityLogoutFlags: flags,
  );
  ref.onDispose(monitor.dispose);
  return monitor;
});
