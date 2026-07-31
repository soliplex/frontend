import 'package:flutter/foundation.dart';

import '../../execution_step.dart';

/// A single row in the execution timeline. A [TimelineStep] groups a
/// step with the activity ids that arrived while it was active; a
/// [TimelineStandaloneActivity] is an activity with no owning step
/// (observed before the first step or after all steps completed).
///
/// An "activity id" is the AG-UI `ActivityMessage.messageId` of the
/// referenced record — the same string carried by
/// `SkillToolCallActivity.messageId` and `ActivityRecord.messageId`.
/// The renderer resolves each id against the tracker's
/// `skillToolCalls` computed signal, which is itself derived from
/// `Conversation.activities`. Storing ids (not decoded objects) keeps
/// activity content sourced from one place and lets a
/// replace-in-place result snapshot update the rendered row without
/// any tracker bookkeeping.
sealed class TimelineEntry {
  const TimelineEntry();
}

/// A step and the detail of the server tool call it represents.
///
/// [args] and [result] belong to the call itself, so they are held on the
/// entry rather than resolved from a separate store: a `TOOL_CALL_START`
/// opens the step, its `TOOL_CALL_ARGS` deltas append to [args], and its
/// `TOOL_CALL_RESULT` sets [result] once. Nothing rewrites them afterwards,
/// which is why they need none of the id-resolution the activity path uses.
///
/// [toolCallId] is null for steps that are not server tool calls (thinking,
/// client-side tool execution); those have no args or result to show.
@immutable
final class TimelineStep extends TimelineEntry {
  const TimelineStep({
    required this.step,
    this.activityIds = const [],
    this.toolCallId,
    this.args = '',
    this.result,
  });

  final ExecutionStep step;
  final List<String> activityIds;
  final String? toolCallId;

  /// Accumulated `TOOL_CALL_ARGS` deltas. Not valid JSON until the call ends.
  final String args;

  /// The call's result body, or null until `TOOL_CALL_RESULT` arrives.
  final String? result;

  TimelineStep withStep(ExecutionStep step) => _copyWith(step: step);

  TimelineStep withActivities(List<String> activityIds) =>
      _copyWith(activityIds: activityIds);

  TimelineStep withDetail({String? args, String? result}) =>
      _copyWith(args: args, result: result);

  TimelineStep _copyWith({
    ExecutionStep? step,
    List<String>? activityIds,
    String? args,
    String? result,
  }) =>
      TimelineStep(
        step: step ?? this.step,
        activityIds: activityIds ?? this.activityIds,
        toolCallId: toolCallId,
        args: args ?? this.args,
        result: result ?? this.result,
      );
}

@immutable
final class TimelineStandaloneActivity extends TimelineEntry {
  const TimelineStandaloneActivity({required this.activityId});

  final String activityId;
}
