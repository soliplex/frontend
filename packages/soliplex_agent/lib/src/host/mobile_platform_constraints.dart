import 'package:soliplex_agent/src/host/platform_constraints.dart';

/// Platform constraints for mobile (iOS, Android).
///
/// Same capabilities as native desktop but with a lower default concurrency
/// limit to conserve memory on resource-constrained devices.
class MobilePlatformConstraints implements PlatformConstraints {
  /// Creates mobile platform constraints.
  ///
  /// [maxConcurrentBridges] defaults to 2 (conservative for mobile memory).
  const MobilePlatformConstraints({this.maxConcurrentBridges = 2});

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
