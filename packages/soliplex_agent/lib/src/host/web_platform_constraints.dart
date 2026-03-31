import 'package:soliplex_agent/src/host/platform_constraints.dart';

/// Platform constraints for web (WASM).
///
/// Web has a single-threaded WASM interpreter. Only one bridge can
/// run at a time, and it cannot be re-entered while suspended.
/// However, multiple HTTP/SSE sessions can run concurrently on the
/// event loop — [maxConcurrentSessions] controls that limit.
class WebPlatformConstraints implements PlatformConstraints {
  /// Creates web platform constraints.
  ///
  /// [maxConcurrentSessions] defaults to 4 — HTTP streams are I/O-bound
  /// and interleave safely on the single-threaded event loop.
  const WebPlatformConstraints({this.maxConcurrentSessions = 4});

  @override
  bool get supportsParallelExecution => false;

  @override
  bool get supportsAsyncMode => false;

  @override
  int get maxConcurrentBridges => 1;

  @override
  bool get supportsReentrantInterpreter => false;

  @override
  final int maxConcurrentSessions;
}
