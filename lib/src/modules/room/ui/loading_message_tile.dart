import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

import '../execution_tracker.dart';
import 'execution/phase_indicator.dart';
import 'execution/execution_timeline.dart';
import 'execution/thinking_block.dart';
import '../../../design/design.dart';

class LoadingMessageTile extends StatelessWidget {
  const LoadingMessageTile({
    super.key,
    required this.roomId,
    required this.messageId,
    this.executionTracker,
    this.streamingPhase,
  });

  final String roomId;
  final String messageId;
  final ExecutionTracker? executionTracker;
  final RunPhase? streamingPhase;

  @override
  Widget build(BuildContext context) {
    if (executionTracker != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (streamingPhase != null) PhaseIndicator(phase: streamingPhase!),
          ExecutionTimeline(
            roomId: roomId,
            messageId: messageId,
            tracker: executionTracker!,
          ),
          ExecutionThinkingBlock(
            roomId: roomId,
            messageId: messageId,
            tracker: executionTracker!,
          ),
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
        SizedBox(width: SoliplexSpacing.s2),
        Text('Thinking...'),
      ],
    );
  }
}
