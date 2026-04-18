import 'dart:async';

/// A unified definition for a tool that can be invoked from Python
/// (via MontyCallback) and from an LLM (via ClientTool).
///
/// This simplifies the "Plugin" architecture by combining metadata
/// and implementation into a single immutable structure.
class SoliplexTool {
  /// Creates a [SoliplexTool] with the given metadata and [handler].
  const SoliplexTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.handler,
    this.requiresApproval = false,
  });

  /// Canonical tool name (e.g. `soliplex_new_thread`).
  final String name;

  /// Human-readable description for the LLM and `help()`.
  final String description;

  /// JSON Schema for the tool's parameters.
  final Map<String, dynamic> parameters;

  /// The Dart implementation of the tool.
  ///
  /// Receives named arguments from Python or the LLM.
  /// Returns a JSON-serializable object.
  final Future<Object?> Function(Map<String, Object?> args) handler;

  /// Whether the agent framework should obtain user approval before
  /// executing this tool.
  final bool requiresApproval;
}
