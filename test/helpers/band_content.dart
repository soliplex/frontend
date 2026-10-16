import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/timeline_entry.dart';

/// Everything [band] holds, as values the matcher compares deeply, so two
/// bands built by different paths are compared by what they would render
/// rather than by identity.
///
/// Leaves out when each step and activity happened: live measures a step by
/// its own clock, and dates an activity whose event carries no time when it
/// processes it, so neither can agree with a reload.
Map<String, Object?> describeBand(ExecutionTracker band) => {
      'timeline': [
        for (final entry in band.timeline.value)
          switch (entry) {
            TimelineStep(
              :final step,
              :final toolCallId,
              :final args,
              :final result,
              :final activityIds,
            ) =>
              {
                'label': step.label,
                'type': step.type,
                'status': step.status,
                'toolCallId': toolCallId,
                'args': args,
                'result': result,
                'activityIds': activityIds,
              },
            TimelineStandaloneActivity(:final activityId) => {
                'activity': activityId,
              },
          },
      ],
      'steps': [
        for (final step in band.steps.value)
          '${step.type}/${step.status}/${step.label}',
      ],
      'thinking': band.thinkingBlocks.value,
      'thinkingStreaming': band.isThinkingStreaming.value,
      'frozen': band.isFrozen,
      'activities': [
        for (final record in band.activities.value)
          {
            'messageId': record.messageId,
            'activityType': record.activityType,
            'content': record.content,
          },
      ],
    };

/// [bands] keyed as given, each described by [describeBand].
Map<String, Object?> describeBands(Map<String, ExecutionTracker> bands) => {
      for (final MapEntry(:key, :value) in bands.entries)
        key: describeBand(value),
    };
