import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Compile-time configuration for the per-server status-message banner.
///
/// `filePath` locates the static JSON file operators drop to post a message,
/// resolved against the server URL via `baseUrl.resolve(filePath)` — a
/// leading-slash path (the `/messages/status.json` default) resolves against
/// the server origin, discarding any base-URL path. `pollInterval` bounds
/// cancel latency to one cycle. Pass [StatusMessageConfig.disabled] (or any
/// zero interval) to opt out; the controller checks [isEnabled] and never
/// schedules a fetch when off.
class StatusMessageConfig {
  const StatusMessageConfig({
    this.filePath = defaultFilePath,
    this.pollInterval = defaultPollInterval,
  }) : assert(filePath.length > 0, 'filePath must be non-empty');

  static const String defaultFilePath = '/messages/status.json';
  static const Duration defaultPollInterval = Duration(minutes: 5);
  static const StatusMessageConfig disabled =
      StatusMessageConfig(pollInterval: Duration.zero);

  final String filePath;
  final Duration pollInterval;

  bool get isEnabled => pollInterval > Duration.zero;
}

/// Holds the active [StatusMessageConfig].
///
/// Overridden by [SoliplexShell] with the value from [ShellConfig.statusMessage];
/// defaults to the built-in config so a bare [ProviderScope] (e.g. a widget
/// test) can read it without an override.
final statusMessageConfigProvider = Provider<StatusMessageConfig>(
  (_) => const StatusMessageConfig(),
);
