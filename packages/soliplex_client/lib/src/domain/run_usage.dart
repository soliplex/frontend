import 'package:meta/meta.dart';

/// What one run cost the model, as the provider itself reported it.
///
/// [inputTokens] is summed across every request the run made, so a tool
/// loop reports several times the context actually sent. [finalInputTokens]
/// is the last request alone, which is what says how full the context
/// window was — and it is null for a run that never reached the model.
///
/// Nothing here is an estimate: the provider counted the request as sent,
/// instructions, tool and MCP schemas, chat template and images included.
@immutable
class RunUsage {
  /// Creates a usage record for [runId].
  const RunUsage({
    required this.runId,
    required this.inputTokens,
    required this.outputTokens,
    required this.requests,
    required this.toolCalls,
    this.finalInputTokens,
    this.resolvedModelName,
  });

  /// The run this usage belongs to.
  final String runId;

  /// Input tokens across every request in the run.
  final int inputTokens;

  /// Output tokens across every request in the run.
  final int outputTokens;

  /// How many model requests the run made.
  final int requests;

  /// How many tool calls the run made.
  final int toolCalls;

  /// Input tokens of the run's last model request, or null when the run
  /// never reached the model.
  final int? finalInputTokens;

  /// The model the provider actually served, which may differ from the
  /// configured name.
  final String? resolvedModelName;

  /// Whether this run says anything about the context window.
  bool get isMeasured => finalInputTokens != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RunUsage &&
          other.runId == runId &&
          other.inputTokens == inputTokens &&
          other.outputTokens == outputTokens &&
          other.requests == requests &&
          other.toolCalls == toolCalls &&
          other.finalInputTokens == finalInputTokens &&
          other.resolvedModelName == resolvedModelName;

  @override
  int get hashCode => Object.hash(
        runId,
        inputTokens,
        outputTokens,
        requests,
        toolCalls,
        finalInputTokens,
        resolvedModelName,
      );

  @override
  String toString() => 'RunUsage($runId, final: ${finalInputTokens ?? "?"}, '
      'model: $resolvedModelName)';
}
