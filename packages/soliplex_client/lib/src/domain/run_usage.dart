import 'package:meta/meta.dart';

/// What one run cost the model, as the provider itself reported it.
///
/// [inputTokens] is summed across every request the run made, so a tool
/// loop reports several times the context actually sent. [finalInputTokens]
/// is the last request alone, which is what says how full the context
/// window was — and it is null for a run that never reached the model.
/// The reply to that request is the thread's newest message, and the next
/// request carries it as input, so [contextTokens] adds
/// [finalOutputTokens] to it.
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
    this.finalOutputTokens,
    this.measuredAt,
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

  /// Output tokens of the run's last model request — the reply the thread
  /// now ends with — or null when the run never reached the model, or the
  /// backend predates the field.
  final int? finalOutputTokens;

  /// When the backend recorded this usage, or null from a backend that
  /// predates the field.
  ///
  /// What says which of two measurements is the newer: a client can learn
  /// of them out of order, and a thread can be run from more than one.
  final DateTime? measuredAt;

  /// Whether this run says anything about the context window.
  bool get isMeasured => finalInputTokens != null;

  /// Tokens the thread occupies after this run, or null when unmeasured.
  ///
  /// The last request's input plus its reply, which the next request will
  /// carry. A backend that reports no reply count leaves the reading one
  /// reply short rather than unmeasured.
  int? get contextTokens {
    final input = finalInputTokens;
    if (input == null) return null;
    return input + (finalOutputTokens ?? 0);
  }

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
          other.resolvedModelName == resolvedModelName &&
          other.finalOutputTokens == finalOutputTokens &&
          other.measuredAt == measuredAt;

  @override
  int get hashCode => Object.hash(
        runId,
        inputTokens,
        outputTokens,
        requests,
        toolCalls,
        finalInputTokens,
        resolvedModelName,
        finalOutputTokens,
        measuredAt,
      );

  @override
  String toString() => 'RunUsage($runId, final: ${finalInputTokens ?? "?"}'
      '+${finalOutputTokens ?? "?"}, model: $resolvedModelName, '
      'at: $measuredAt)';
}
