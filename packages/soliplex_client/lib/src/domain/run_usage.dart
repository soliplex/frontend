import 'package:meta/meta.dart';

/// What one run cost the model, as the provider itself reported it.
///
/// [finalInputTokens] is the last request alone, which is what says how full
/// the context window was — and it is null when the model never answered in
/// the run. The reply to that request is the thread's newest message, and
/// the next request carries it as input, so [contextTokens] adds
/// [finalOutputTokens] to it.
///
/// Nothing here is an estimate: the provider counted the request as sent,
/// instructions, tool and MCP schemas, chat template and images included.
@immutable
class RunUsage {
  /// Creates a usage record for [runId].
  const RunUsage({
    required this.runId,
    this.finalInputTokens,
    this.finalOutputTokens,
  });

  /// The run this usage belongs to.
  final String runId;

  /// Input tokens of the run's last model request — how full the context
  /// window was when it went out — or null when the model never answered in
  /// the run.
  final int? finalInputTokens;

  /// Output tokens of the run's last model request — the reply the thread
  /// now ends with — or null when the model never answered in the run, or
  /// the backend predates the field.
  final int? finalOutputTokens;

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
          other.finalInputTokens == finalInputTokens &&
          other.finalOutputTokens == finalOutputTokens;

  @override
  int get hashCode => Object.hash(runId, finalInputTokens, finalOutputTokens);

  @override
  String toString() => 'RunUsage($runId, final: ${finalInputTokens ?? "?"}'
      '+${finalOutputTokens ?? "?"})';
}

/// A run's usage, and how much of the thread's transcript it counted.
///
/// The usage is the provider's count of the run's last request and its
/// reply. That request and reply are the transcript's first
/// [coveredMessages] messages: the transcript's length when the run ended.
/// Whatever the transcript gains after that is not in the count.
@immutable
class MeasuredRun {
  /// Creates a measurement of [usage] covering [coveredMessages].
  const MeasuredRun({required this.usage, required this.coveredMessages});

  /// The run's recorded usage.
  final RunUsage usage;

  /// How many of the transcript's messages [usage] counted.
  final int coveredMessages;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MeasuredRun &&
          other.usage == usage &&
          other.coveredMessages == coveredMessages;

  @override
  int get hashCode => Object.hash(usage, coveredMessages);

  @override
  String toString() => 'MeasuredRun($usage, covers $coveredMessages)';
}
