import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../modules/auth/auth_providers.dart';
import 'inactivity_config.dart';
import 'inactivity_monitor.dart';

/// Holds the active [InactivityConfig].
///
/// Overridden by [SoliplexShell] with the value from [ShellConfig.inactivity].
final inactivityConfigProvider = Provider<InactivityConfig>(
  (_) => throw UnimplementedError('must be overridden by SoliplexShell'),
);

/// The shell-scoped [InactivityMonitor].
///
/// Wired with the [ServerManager.servers] signal, the active
/// [InactivityConfig], and the [InactivityLogoutFlagStorage] so it can
/// flag servers whose tokens it drops at grace-timer expiry.
final inactivityMonitorProvider = Provider<InactivityMonitor>((ref) {
  final monitor = InactivityMonitor(
    servers: ref.watch(serverManagerProvider).servers,
    config: ref.watch(inactivityConfigProvider),
    inactivityLogoutFlags: ref.watch(inactivityLogoutFlagsProvider),
  );
  ref.onDispose(monitor.dispose);
  return monitor;
});
