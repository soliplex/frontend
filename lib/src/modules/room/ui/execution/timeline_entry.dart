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

@immutable
final class TimelineStep extends TimelineEntry {
  const TimelineStep({required this.step, this.activityIds = const []});

  final ExecutionStep step;
  final List<String> activityIds;

  TimelineStep withStep(ExecutionStep step) =>
      TimelineStep(step: step, activityIds: activityIds);

  TimelineStep withActivities(List<String> activityIds) =>
      TimelineStep(step: step, activityIds: activityIds);
}

@immutable
final class TimelineStandaloneActivity extends TimelineEntry {
  const TimelineStandaloneActivity({required this.activityId});

  final String activityId;
}
