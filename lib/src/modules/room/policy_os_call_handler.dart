import 'package:dart_monty/dart_monty_bridge.dart'
    show OsCallHandler, OsCallPermissionError;

import 'access_policy.dart';

/// Wraps an [OsCallHandler] and enforces [AccessPolicy.osFilter].
///
/// Every OS call from Python passes through [handle] before reaching [_inner].
/// Denied operations throw [OsCallPermissionError], which the bridge
/// translates into a Python `PermissionError` — the LLM sees a structured
/// error, not a crash.
///
/// [policy] is mutable so it can be tightened when room server config arrives
/// without rebuilding the [MontyScriptEnvironment].
///
/// Usage:
/// ```dart
/// final osHandler = PolicyOsCallHandler(inner: defaultSandboxOsHandler());
/// final env = MontyScriptEnvironment(tools: [...], os: osHandler.handle);
/// // Later, when room config arrives:
/// osHandler.policy = AccessPolicy.fromRoomConfig(...);
/// ```
class PolicyOsCallHandler {
  /// Creates a [PolicyOsCallHandler] wrapping [inner].
  PolicyOsCallHandler({
    required OsCallHandler inner,
    AccessPolicy policy = AccessPolicy.permissive,
  })  : _inner = inner,
        _policy = policy;

  final OsCallHandler _inner;
  AccessPolicy _policy;

  /// Updates the active policy (e.g. when room server config arrives).
  // ignore: avoid_setters_without_getters
  set policy(AccessPolicy value) => _policy = value;

  /// The [OsCallHandler] to register on [MontyScriptEnvironment].
  OsCallHandler get handler => _handle;

  Future<Object?> _handle(
    String operation,
    List<Object?> args,
    Map<String, Object?>? kwargs,
  ) {
    if (!_policy.osFilter.allows(operation)) {
      throw OsCallPermissionError(
        operation,
        'OS operation "$operation" is not permitted in this session',
      );
    }
    return _inner(operation, args, kwargs);
  }
}
