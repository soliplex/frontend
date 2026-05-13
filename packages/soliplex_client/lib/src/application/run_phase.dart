import 'package:meta/meta.dart';

/// Current phase of a run.
///
/// Represents what the backend is currently doing. Persists until the next
/// phase starts (not when the current one ends), ensuring the UI can
/// display the phase even for rapid events.
@immutable
sealed class RunPhase {
  const RunPhase();
}

/// No specific phase - initial state or processing.
@immutable
class ProcessingPhase extends RunPhase {
  /// Creates a processing phase.
  const ProcessingPhase();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ProcessingPhase;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'ProcessingPhase()';
}

/// Model is thinking/reasoning.
@immutable
class ThinkingPhase extends RunPhase {
  /// Creates a thinking phase.
  const ThinkingPhase();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ThinkingPhase;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'ThinkingPhase()';
}

/// One or more tools are being called.
@immutable
class ToolCallPhase extends RunPhase {
  /// Creates a tool call phase with a single tool name.
  const ToolCallPhase({
    required String toolName,
    this.latestToolCallId,
    this.timestamp,
  })  : toolNames = const {},
        _singleToolName = toolName;

  /// Creates a tool call phase with multiple tool names.
  const ToolCallPhase.multiple({
    required this.toolNames,
    this.latestToolCallId,
    this.timestamp,
  }) : _singleToolName = null;

  /// Names of tools being/have been called in this phase.
  final Set<String> toolNames;

  /// Single tool name for backward compatibility constructor.
  final String? _singleToolName;

  /// ID of the most recent tool call that updated this phase.
  final String? latestToolCallId;

  /// Timestamp of the most recent event that updated this phase.
  final int? timestamp;

  /// All tool names (handles both constructors).
  Set<String> get allToolNames =>
      _singleToolName != null ? {_singleToolName} : toolNames;

  /// Creates a new phase with an additional tool name.
  ToolCallPhase withToolName(
    String name, {
    String? latestToolCallId,
    int? timestamp,
  }) {
    return ToolCallPhase.multiple(
      toolNames: {...allToolNames, name},
      latestToolCallId: latestToolCallId ?? this.latestToolCallId,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolCallPhase &&
          _setEquals(allToolNames, other.allToolNames) &&
          latestToolCallId == other.latestToolCallId &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(
        runtimeType,
        Object.hashAll(allToolNames.toList()..sort()),
        latestToolCallId,
        timestamp,
      );

  @override
  String toString() => 'ToolCallPhase(toolNames: $allToolNames, '
      'latestToolCallId: $latestToolCallId, timestamp: $timestamp)';

  static bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final item in a) {
      if (!b.contains(item)) return false;
    }
    return true;
  }
}

/// Model is responding with text.
@immutable
class RespondingPhase extends RunPhase {
  /// Creates a responding phase.
  const RespondingPhase();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RespondingPhase;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'RespondingPhase()';
}
