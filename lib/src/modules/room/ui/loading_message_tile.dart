import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

import '../execution_tracker.dart';
import 'execution/phase_indicator.dart';
import 'execution/execution_timeline.dart';
import 'execution/thinking_block.dart';
import 'package:soliplex_design/soliplex_design.dart';

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
    // No execution detail yet: stand in with an animated skeleton of the
    // assistant reply, shaped like a real assistant bubble so the placeholder
    // reads as an incoming message (and doesn't jump when the text lands).
    final theme = Theme.of(context);
    final rounded = Radius.circular(context.radii.md);
    final tight = Radius.circular(context.radii.sm);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (streamingPhase != null) PhaseIndicator(phase: streamingPhase!),
        Text(
          'Assistant',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: SoliplexSpacing.s1),
        Container(
          // design-system exception: 14/10 is the documented chat-bubble
          // padding (see design_system/README.md), matching _MessageBubble.
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.only(
              topLeft: rounded,
              topRight: rounded,
              bottomLeft: tight,
              bottomRight: rounded,
            ),
          ),
          child: const SoliplexShimmer(lineFractions: [1, 1, 0.55]),
        ),
      ],
    );
  }
}
