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
    // The auth-module providers throw UnimplementedError when not
    // overridden, but riverpod wraps that in a ProviderException that it
    // doesn't export — so it can't be caught by type. In practice this is
    // the only thing this catch ever sees: those providers are always
    // installed via overrideWithValue (a pre-built instance that can't
    // throw at read time), so there is no "installed but errored" case to
    // distinguish. Returning null keeps the shell bootable for consumers
    // that don't include the auth module.
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
