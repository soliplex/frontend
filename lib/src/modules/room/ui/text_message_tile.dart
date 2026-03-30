import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import '../execution_tracker.dart';
import 'execution/activity_indicator.dart';
import 'execution/step_log.dart';
import 'execution/thinking_block.dart';
import 'copy_button.dart';
import 'feedback_buttons.dart';
import 'markdown/flutter_markdown_plus_renderer.dart';

class TextMessageTile extends StatelessWidget {
  const TextMessageTile({
    super.key,
    required this.message,
    this.runId,
    this.onFeedbackSubmit,
    this.executionTracker,
    this.streamingActivity,
  });

  final TextMessage message;
  final String? runId;
  final void Function(FeedbackType feedback, String? reason)? onFeedbackSubmit;
  final ExecutionTracker? executionTracker;
  final ActivityType? streamingActivity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.user == ChatUser.user;
    final showFeedback = !isUser && onFeedbackSubmit != null;
    final hasTracker = executionTracker != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (streamingActivity != null)
          ActivityIndicator(activity: streamingActivity!),
        if (hasTracker) StepLog(tracker: executionTracker!),
        if (hasTracker)
          ExecutionThinkingBlock(tracker: executionTracker!)
        else if (!isUser && message.hasThinkingText)
          _ThinkingBlock(text: message.thinkingText),
        Text(
          isUser ? 'You' : 'Assistant',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isUser
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: isUser
              ? SelectableText(message.text)
              : message.text.isEmpty
                  ? const Text('...')
                  : FlutterMarkdownPlusRenderer(data: message.text),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            CopyButton(text: message.text),
            if (showFeedback) ...[
              const SizedBox(width: 8),
              FeedbackButtons(onFeedbackSubmit: onFeedbackSubmit!),
            ],
          ],
        ),
      ],
    );
  }
}

class _ThinkingBlock extends StatelessWidget {
  const _ThinkingBlock({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      title: Row(
        children: [
          Expanded(
            child: Text(
              'Thinking...',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          CopyButton(
            text: text,
            tooltip: 'Copy thinking',
            iconSize: 16,
          ),
        ],
      ),
      dense: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 4),
      children: [
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            fontStyle: FontStyle.italic,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
