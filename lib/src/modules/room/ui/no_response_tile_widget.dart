import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import '../execution_tracker.dart';
import 'execution/phase_indicator.dart';
import 'execution/execution_timeline.dart';
import 'execution/static_thinking_block.dart';
import 'execution/thinking_block.dart';
import 'message_caption.dart';
import 'package:soliplex_design/soliplex_design.dart';

class NoResponseTileWidget extends StatelessWidget {
  const NoResponseTileWidget({
    super.key,
    required this.roomId,
    required this.message,
    this.executionTracker,
    this.streamingPhase,
  });

  final String roomId;
  final NoResponseTile message;
  final ExecutionTracker? executionTracker;
  final RunPhase? streamingPhase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasTracker = executionTracker != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (streamingPhase != null) PhaseIndicator(phase: streamingPhase!),
        if (hasTracker)
          ExecutionTimeline(
            roomId: roomId,
            messageId: message.id,
            tracker: executionTracker!,
          ),
        if (hasTracker)
          ExecutionThinkingBlock(
            roomId: roomId,
            messageId: message.id,
            tracker: executionTracker!,
          )
        else if (message.hasThinkingText)
          StaticThinkingBlock(
            roomId: roomId,
            messageId: message.id,
            text: message.thinkingText,
          ),
        Text(
          'Assistant',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: SoliplexSpacing.s1),
        _TerminalReasonBubble(
          reason: message.reason,
          errorDetail: message.errorDetail,
        ),
        if (message.createdAt != null) MessageCaption(time: message.createdAt!),
      ],
    );
  }
}

class _TerminalReasonBubble extends StatelessWidget {
  const _TerminalReasonBubble({required this.reason, this.errorDetail});

  final TerminalReason reason;
  final String? errorDetail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, label) = switch (reason) {
      TerminalReason.finished => (
          Icons.info_outline,
          'Run finished without a response',
        ),
      TerminalReason.failed => (
          Icons.error_outline,
          (errorDetail != null && errorDetail!.isNotEmpty)
              ? 'Run failed: $errorDetail'
              : 'Run failed without a response',
        ),
      TerminalReason.cancelled => (
          Icons.cancel_outlined,
          'Run cancelled without a response',
        ),
    };
    return Container(
      // design-system exception: 14/10 is the documented chat-bubble
      // padding (see design_system/README.md "the only 14").
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(context.radii.md),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onTertiaryContainer),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
