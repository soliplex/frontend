import 'package:meta/meta.dart';

/// An MCP client toolset configured in a room.
///
/// Represents an external MCP server that the room connects to
/// as a client.
@immutable
class McpClientToolset {
  /// Creates an MCP client toolset.
  const McpClientToolset({
    required this.kind,
    this.allowedTools = const [],
    this.toolsetParams = const {},
  });

  /// Transport kind (e.g., 'stdio', 'http').
  final String kind;

  /// Tools this toolset is restricted to. Empty means no restriction: the
  /// backend reads a missing and an empty allow-list as the same state,
  /// every tool the server offers.
  final List<String> allowedTools;

  /// Transport parameters (e.g., url for http, command for stdio).
  final Map<String, dynamic> toolsetParams;

  @override
  String toString() => 'McpClientToolset(kind: $kind)';
}
