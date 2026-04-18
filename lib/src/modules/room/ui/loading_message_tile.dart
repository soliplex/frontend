import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

import '../execution_tracker.dart';
import 'execution/activity_indicator.dart';
import 'execution/activity_log.dart';
import 'execution/step_log.dart';

class LoadingMessageTile extends StatelessWidget {
  const LoadingMessageTile({
    super.key,
    this.executionTracker,
    this.streamingActivity,
  });

  final ExecutionTracker? executionTracker;
  final ActivityType? streamingActivity;

  @override
  Widget build(BuildContext context) {
    if (executionTracker != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (streamingActivity != null)
            ActivityIndicator(activity: streamingActivity!),
          StepLog(tracker: executionTracker!),
          ActivityLog(tracker: executionTracker!),
        ],
      );
    }
    return const Row(
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 8),
        Text('Thinking...'),
      ],
    );
  }
}
