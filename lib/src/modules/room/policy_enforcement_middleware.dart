import 'package:dart_monty/dart_monty_bridge.dart'
    show BridgeMiddleware, CallRole, InfraCall, ToolHandler;

import 'access_policy.dart';

/// Bridge middleware that enforces an [AccessPolicy] on every tool call.
///
/// Infrastructure calls ([InfraCall]) always bypass the policy — they are
/// internal orchestration ops (`__restore_state__`, `__persist_state__`, etc.)
/// that must never be gated.
///
/// [policy] is mutable so it can be updated when a room session delivers
/// its server-side configuration without re-registering the middleware.
class PolicyEnforcementMiddleware implements BridgeMiddleware {
  /// Creates a [PolicyEnforcementMiddleware] with the given [policy].
  PolicyEnforcementMiddleware(AccessPolicy policy) : _policy = policy;

  AccessPolicy _policy;

  /// Updates the active policy (e.g. when room server config arrives).
  // ignore: avoid_setters_without_getters
  set policy(AccessPolicy value) => _policy = value;

  @override
  Future<Object?> handle(
    String name,
    Map<String, Object?> args,
    CallRole role,
    ToolHandler next,
  ) {
    if (role is InfraCall) return next(name, args);
    if (!_policy.toolFilter.allows(name)) {
      throw StateError('Tool "$name" is not permitted in this session');
    }
    return next(name, args);
  }
}
