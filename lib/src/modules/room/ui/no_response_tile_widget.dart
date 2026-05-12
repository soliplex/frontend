import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import '../execution_tracker.dart';
import 'execution/activity_indicator.dart';
import 'execution/execution_timeline.dart';
import 'execution/static_thinking_block.dart';
import 'execution/thinking_block.dart';

class NoResponseTileWidget extends StatelessWidget {
  const NoResponseTileWidget({
    super.key,
    required this.roomId,
    required this.message,
    this.executionTracker,
    this.streamingActivity,
  });

  final String roomId;
  final NoResponseTile message;
  final ExecutionTracker? executionTracker;
  final ActivityType? streamingActivity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasTracker = executionTracker != null;

    return Column(
      crossAxisAlignment: .start,
      children: [
        if (streamingActivity != null)
          ActivityIndicator(activity: streamingActivity!),
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
        const SizedBox(height: 4),
        _TerminalReasonBubble(
          reason: message.reason,
          errorDetail: message.errorDetail,
        ),
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
    final detail = errorDetail;
    final (icon, label) = switch (reason) {
      .finished => (Icons.info_outline, 'Run finished without a response'),
      .failed => (
        Icons.error_outline,
        (detail != null && detail.isNotEmpty)
            ? 'Run failed: $detail'
            : 'Run failed without a response',
      ),
      .cancelled => (Icons.cancel_outlined, 'Run cancelled without a response'),
    };
    return Container(
      padding: const .symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: .circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
                fontStyle: .italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
