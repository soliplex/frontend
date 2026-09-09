import 'package:meta/meta.dart';

/// How full a thread's context window is, as far as anything knows.
///
/// Every field is optional, and a null is an answer rather than a
/// failure. [maxModelLen] is null when the provider does not report a
/// window — the OpenAI API and Ollama's compatibility surface do not —
/// and [measuredTokens] is null until a run in the thread has reached
/// the model.
///
/// [measuredTokens] is not an estimate. It is what the provider itself
/// reported for the last request of the newest measured run, so it
/// already counts everything this client never sees: the agent's
/// instructions, capability instructions, tool and MCP schemas, the
/// chat template, images, and any evidence compaction the backend
/// applied on the way out.
@immutable
class ThreadContext {
  /// Creates a reading.
  const ThreadContext({
    this.maxModelLen,
    this.modelName,
    this.measuredTokens,
    this.measuredAtRunId,
  });

  /// A reading for a thread nothing is known about yet.
  const ThreadContext.unknown()
      : maxModelLen = null,
        modelName = null,
        measuredTokens = null,
        measuredAtRunId = null;

  /// The model's context window, or null when the provider does not say.
  ///
  /// Null must not be filled in with a guess. Ollama advertises gpt-oss
  /// at 131072 while the loaded runner serves 32768, and a denominator
  /// four times too large reads as emptier than reality.
  final int? maxModelLen;

  /// The model the room's agent is configured to use.
  final String? modelName;

  /// Measured input tokens of the newest measured run's final request.
  final int? measuredTokens;

  /// Which run [measuredTokens] was measured on.
  final String? measuredAtRunId;

  /// Whether a percentage can be shown at all.
  bool get hasWindow => maxModelLen != null && maxModelLen! > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThreadContext &&
          other.maxModelLen == maxModelLen &&
          other.modelName == modelName &&
          other.measuredTokens == measuredTokens &&
          other.measuredAtRunId == measuredAtRunId;

  @override
  int get hashCode => Object.hash(
        maxModelLen,
        modelName,
        measuredTokens,
        measuredAtRunId,
      );

  @override
  String toString() => 'ThreadContext(${measuredTokens ?? "?"} / '
      '${maxModelLen ?? "?"}, model: $modelName)';
}
