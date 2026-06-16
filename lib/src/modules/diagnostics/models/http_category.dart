import 'http_event_group.dart';

/// Coarse functional bucket for an HTTP exchange, inferred from its endpoint.
/// Drives the Network Inspector's category filter.
enum HttpCategory {
  /// AG-UI agent / model execution (runs, streaming turns, history, feedback).
  llm,

  /// Identity endpoints — `user_info` and any OIDC discovery/token calls that
  /// flow through the inspected client.
  auth,

  /// Everything else the backend exposes (rooms, documents, uploads, quizzes,
  /// chunks, stats, installation/versions, mcp_token, …).
  system,
}

/// Markers (matched against lowercased path segments) that flag an identity
/// endpoint. `mcp_token` is deliberately absent — it's an MCP tooling token,
/// not user auth, so it stays [HttpCategory.system].
const _authSegments = {
  'user_info',
  'userinfo',
  '.well-known',
  'openid-connect',
  'oauth',
  'authorize',
};

/// Infers the [HttpCategory] of a grouped exchange from its request URL.
/// Auth is checked before LLM; AG-UI paths never carry an auth marker, so the
/// order only matters for safety.
HttpCategory categoryOf(HttpEventGroup group) {
  final segments = group.uri.pathSegments.map((s) => s.toLowerCase());
  if (segments.any(_authSegments.contains)) return HttpCategory.auth;
  if (segments.contains('agui')) return HttpCategory.llm;
  return HttpCategory.system;
}
