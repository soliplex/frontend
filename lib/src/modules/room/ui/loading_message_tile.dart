import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

import '../execution_tracker.dart';
import 'execution/activity_indicator.dart';
import 'execution/step_log.dart';
import 'execution/thinking_block.dart';
import '../../../../soliplex_frontend.dart';

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
          ExecutionThinkingBlock(tracker: executionTracker!),
        ],
      );
    }
    return const Row(
      children: [
        SizedBox(
          width: SoliplexSpacing.s4,
          height: SoliplexSpacing.s4,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: SoliplexSpacing.s2),
        Text('Thinking...'),
      ],
    );
  }
}
