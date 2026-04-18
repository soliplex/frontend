import 'package:meta/meta.dart';

/// Determines which client-side tools are callable from a room session.
///
/// `allowedTools` is an allowlist by tool name or namespace prefix.
/// Namespaces are derived by splitting on `_` and taking the first segment:
/// `soliplex_list_rooms` → namespace `soliplex`.
///
/// If [allowedTools] is null, all tools are permitted (fail-open default).
/// If [allowedNamespaces] is null, all namespaces are permitted.
/// Denylist ([deniedTools]) is applied after the allowlist.
@immutable
class ToolFilter {
  /// Creates a [ToolFilter].
  const ToolFilter({
    this.allowedTools,
    this.allowedNamespaces,
    this.deniedTools = const {},
  });

  /// Permissive filter — everything allowed, nothing denied.
  static const permissive = ToolFilter();

  /// Tool names that are explicitly allowed. `null` = all allowed.
  final Set<String>? allowedTools;

  /// Namespace prefixes that are explicitly allowed. `null` = all allowed.
  final Set<String>? allowedNamespaces;

  /// Tool names that are explicitly denied (applied after allowlist).
  final Set<String> deniedTools;

  /// Returns true if [toolName] is permitted by this filter.
  bool allows(String toolName) {
    if (deniedTools.contains(toolName)) return false;
    final ns = _namespace(toolName);
    if (allowedNamespaces != null && !allowedNamespaces!.contains(ns)) {
      return false;
    }
    if (allowedTools != null && !allowedTools!.contains(toolName)) {
      return false;
    }
    return true;
  }

  static String _namespace(String toolName) {
    final idx = toolName.indexOf('_');
    return idx < 0 ? toolName : toolName.substring(0, idx);
  }

  /// Builds a [ToolFilter] from a server-supplied allowlist.
  factory ToolFilter.fromAllowlist(List<String>? allowedTools) {
    if (allowedTools == null) return ToolFilter.permissive;
    return ToolFilter(allowedTools: Set.unmodifiable(allowedTools));
  }
}

/// HITL (Human-in-the-Loop) policy — which tool calls require user approval.
@immutable
class HitlPolicy {
  /// Creates a [HitlPolicy].
  const HitlPolicy({
    this.requireApprovalForTools = const {},
    this.requireApprovalForNamespaces = const {},
  });

  /// No tools require approval.
  static const none = HitlPolicy();

  /// Tool names that always require human approval before execution.
  final Set<String> requireApprovalForTools;

  /// Namespaces where every tool requires human approval.
  final Set<String> requireApprovalForNamespaces;

  /// Returns true if [toolName] requires human approval.
  bool requires(String toolName) {
    if (requireApprovalForTools.contains(toolName)) return true;
    final ns = _namespaceOf(toolName);
    return requireApprovalForNamespaces.contains(ns);
  }

  static String _namespaceOf(String toolName) {
    final idx = toolName.indexOf('_');
    return idx < 0 ? toolName : toolName.substring(0, idx);
  }
}

/// Unified access control policy for a Monty scripting session.
///
/// Governs which tools are callable, and when human approval is required.
/// Host filtering (allowHosts/denyHosts) is enforced at the HTTP layer;
/// OsCall filtering is enforced via the OsCallHandler — both reference
/// this model for their configuration.
@immutable
class AccessPolicy {
  /// Creates an [AccessPolicy].
  const AccessPolicy({
    this.toolFilter = ToolFilter.permissive,
    this.hitlPolicy = HitlPolicy.none,
    this.allowHosts,
    this.denyHosts = const {},
  });

  /// Fully permissive policy — no restrictions, no HITL.
  static const permissive = AccessPolicy();

  /// Which tools are callable.
  final ToolFilter toolFilter;

  /// Which tool calls require human approval.
  final HitlPolicy hitlPolicy;

  /// Hostnames the HTTP client may connect to. `null` = unrestricted.
  final Set<String>? allowHosts;

  /// Hostnames the HTTP client must not connect to.
  final Set<String> denyHosts;

  /// Returns true if [host] is permitted by this policy.
  bool hostAllowed(String host) {
    if (denyHosts.contains(host)) return false;
    if (allowHosts != null && !allowHosts!.contains(host)) return false;
    return true;
  }

  /// Builds a policy from server-supplied room client config.
  factory AccessPolicy.fromRoomConfig({
    List<String>? allowedTools,
    List<String>? allowHosts,
    List<String>? denyHosts,
    List<String>? requireApprovalForTools,
    List<String>? requireApprovalForNamespaces,
  }) {
    return AccessPolicy(
      toolFilter: ToolFilter.fromAllowlist(allowedTools),
      hitlPolicy: HitlPolicy(
        requireApprovalForTools: Set.unmodifiable(requireApprovalForTools ?? []),
        requireApprovalForNamespaces:
            Set.unmodifiable(requireApprovalForNamespaces ?? []),
      ),
      allowHosts:
          allowHosts != null ? Set.unmodifiable(allowHosts) : null,
      denyHosts: Set.unmodifiable(denyHosts ?? []),
    );
  }

  /// Returns a copy with [sessionAllowances] added to the tool allowlist.
  AccessPolicy withSessionAllowances(Set<String> sessionAllowances) {
    if (sessionAllowances.isEmpty) return this;
    final current = toolFilter.allowedTools;
    final merged = current != null
        ? {...current, ...sessionAllowances}
        : null; // null = all allowed; session grants don't restrict further
    return AccessPolicy(
      toolFilter: ToolFilter(
        allowedTools: merged != null ? Set.unmodifiable(merged) : null,
        allowedNamespaces: toolFilter.allowedNamespaces,
        deniedTools: toolFilter.deniedTools,
      ),
      hitlPolicy: hitlPolicy,
      allowHosts: allowHosts,
      denyHosts: denyHosts,
    );
  }
}
