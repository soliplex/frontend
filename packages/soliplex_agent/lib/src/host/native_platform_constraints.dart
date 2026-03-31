import 'package:soliplex_agent/src/host/platform_constraints.dart';

/// Platform constraints for native (iOS, Android, macOS, Linux, Windows).
///
/// Native platforms run each Monty bridge in its own Isolate, enabling
/// full parallelism and re-entrant interpreter access.
class NativePlatformConstraints implements PlatformConstraints {
  /// Creates native platform constraints.
  ///
  /// [maxConcurrentBridges] defaults to 4 (reasonable for mobile).
  const NativePlatformConstraints({this.maxConcurrentBridges = 4});

  @override
  bool get supportsParallelExecution => true;

  @override
  bool get supportsAsyncMode => false;

  @override
  final int maxConcurrentBridges;

  @override
  bool get supportsReentrantInterpreter => true;

  @override
  int get maxConcurrentSessions => maxConcurrentBridges;
}
