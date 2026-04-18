import 'package:dart_monty/dart_monty_bridge.dart'
    show BridgeMiddleware, CallRole, InfraCall, ToolHandler;
import 'package:soliplex_agent/soliplex_agent.dart'
    show AllowOnce, AllowSession, ApprovalResult, Deny;

import 'access_policy.dart';

/// Callback invoked when a tool requires HITL approval.
///
/// Returns the user's [ApprovalResult]. Called from the bridge's async
/// context — safe to show a Flutter dialog.
typedef HitlCallback = Future<ApprovalResult> Function(
  String toolName,
  Map<String, Object?> arguments,
);

/// Bridge middleware that enforces an [AccessPolicy] on every tool call.
///
/// Infrastructure calls ([InfraCall]) always bypass the policy — they are
/// internal orchestration ops (`__restore_state__`, `__persist_state__`, etc.)
/// that must never be gated.
///
/// [policy] is mutable so it can be updated when a room session delivers
/// its server-side configuration without re-registering the middleware.
///
/// When [onHitl] is set and [policy.hitlPolicy] requires approval for a tool,
/// the middleware suspends the call and waits for the user's decision. If the
/// user denies, [onDeny] is called and a [StateError] is thrown to abort the
/// tool call.
class PolicyEnforcementMiddleware implements BridgeMiddleware {
  /// Creates a [PolicyEnforcementMiddleware] with the given [policy].
  PolicyEnforcementMiddleware(
    AccessPolicy policy, {
    HitlCallback? onHitl,
    void Function()? onDeny,
  })  : _policy = policy,
        _onHitl = onHitl,
        _onDeny = onDeny;

  AccessPolicy _policy;
  final HitlCallback? _onHitl;
  final void Function()? _onDeny;

  /// Tool names approved for the remainder of the session.
  final Set<String> _sessionApproved = {};

  /// Updates the active policy (e.g. when room server config arrives).
  // ignore: avoid_setters_without_getters
  set policy(AccessPolicy value) => _policy = value;

  @override
  Future<Object?> handle(
    String name,
    Map<String, Object?> args,
    CallRole role,
    ToolHandler next,
  ) async {
    if (role is InfraCall) return next(name, args);

    if (!_policy.toolFilter.allows(name)) {
      throw StateError('Tool "$name" is not permitted in this session');
    }

    final onHitl = _onHitl;
    if (onHitl != null &&
        _policy.hitlPolicy.requires(name) &&
        !_sessionApproved.contains(name)) {
      final result = await onHitl(name, args);
      switch (result) {
        case AllowOnce():
          break;
        case AllowSession():
          _sessionApproved.add(name);
        case Deny():
          _onDeny?.call();
          throw StateError('User denied tool "$name"');
      }
    }

    return next(name, args);
  }
}
