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

/// A timeline step, plus the detail of the server tool call it represents when
/// it is one.
///
/// [args] and [result] belong to the call itself, so they are folded onto the
/// entry rather than resolved at paint time the way an activity id is: a
/// `TOOL_CALL_START` opens the step, its `TOOL_CALL_ARGS` deltas append to
/// [args], and its `TOOL_CALL_RESULT` sets [result]. There is no separate
/// store that could rewrite them in place, so the renderer has nothing to
/// re-resolve them against.
///
/// [toolCallId] is null when the step is not a server tool call, in which case
/// it carries no detail of its own.
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

  /// Accumulated `TOOL_CALL_ARGS` deltas. May be a partial JSON prefix while
  /// the call streams, so callers must tolerate a parse failure — the frontend
  /// never observes the end of the args stream, because `TOOL_CALL_END` does
  /// not bridge to an execution event.
  final String args;

  /// The call's result body. Null until `TOOL_CALL_RESULT` arrives, which is
  /// how a run's completion tells a call still in flight from one that returned
  /// an empty body and warns only about the former. The renderer draws no
  /// result block for either.
  final String? result;

  TimelineStep withStep(ExecutionStep step) => _copyWith(step: step);

  TimelineStep withActivities(List<String> activityIds) =>
      _copyWith(activityIds: activityIds);

  /// Extends [args] by [delta], so the tracker's delta arm cannot accidentally
  /// assign in place of appending.
  TimelineStep appendArgs(String delta) => _copyWith(args: args + delta);

  TimelineStep withResult(String result) => _copyWith(result: result);

  /// [toolCallId] is deliberately not a parameter: a row's identity as a tool
  /// call is fixed when it opens, and every copy carries it through.
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
