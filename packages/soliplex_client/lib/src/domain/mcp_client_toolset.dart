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
    this.allowedTools,
    this.toolsetParams = const {},
  });

  /// Transport kind (e.g., 'stdio', 'http').
  final String kind;

  /// Tools this toolset is restricted to, or null for no restriction.
  ///
  /// Never empty: the backend treats an empty allow-list and a missing one
  /// as the same state — every tool the server offers — so the mapper
  /// normalises both to null.
  final List<String>? allowedTools;

  /// Transport parameters (e.g., url for http, command for stdio).
  final Map<String, dynamic> toolsetParams;

  @override
  String toString() => 'McpClientToolset(kind: $kind)';
}
