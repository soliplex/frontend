import 'package:flutter/foundation.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import '../../execution_step.dart';

/// A single row in the execution timeline. A [TimelineStep] groups a
/// step with the activities that arrived while it was active; a
/// [TimelineStandaloneActivity] is an activity with no owning step
/// (observed before the first step or after all steps completed).
sealed class TimelineEntry {
  const TimelineEntry();
}

@immutable
final class TimelineStep extends TimelineEntry {
  const TimelineStep({required this.step, this.activities = const []});

  final ExecutionStep step;
  final List<SkillToolCallActivity> activities;

  TimelineStep withStep(ExecutionStep step) =>
      TimelineStep(step: step, activities: activities);

  TimelineStep withActivities(List<SkillToolCallActivity> activities) =>
      TimelineStep(step: step, activities: activities);
}

@immutable
final class TimelineStandaloneActivity extends TimelineEntry {
  const TimelineStandaloneActivity({required this.activity});

  final SkillToolCallActivity activity;
}
