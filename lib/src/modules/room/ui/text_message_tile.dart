import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import '../../../../soliplex_frontend.dart';
import '../execution_tracker.dart';
import '../room_providers.dart';
import 'citations_section.dart';
import 'execution/activity_indicator.dart';
import 'execution/execution_timeline.dart';
import 'execution/thinking_block.dart';
import 'copy_button.dart';
import 'feedback_buttons.dart';
import 'markdown/flutter_markdown_plus_renderer.dart';

class TextMessageTile extends StatelessWidget {
  const TextMessageTile({
    super.key,
    required this.roomId,
    required this.message,
    this.runId,
    this.sourceReferences,
    this.onFeedbackSubmit,
    this.onInspect,
    this.onShowChunkVisualization,
    this.executionTracker,
    this.streamingActivity,
  });

  final String roomId;
  final TextMessage message;
  final String? runId;
  final List<SourceReference>? sourceReferences;
  final void Function(FeedbackType feedback, String? reason)? onFeedbackSubmit;
  final VoidCallback? onInspect;
  final void Function(SourceReference)? onShowChunkVisualization;
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
        else if (!isUser && message.hasThinkingText)
          _ThinkingBlock(
            roomId: roomId,
            messageId: message.id,
            text: message.thinkingText,
          ),
        Text(
          isUser ? 'You' : 'Assistant',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: SoliplexSpacing.s1),
        Container(
          padding: isUser
              ? const EdgeInsets.symmetric(
                  horizontal: SoliplexSpacing.s5, vertical: SoliplexSpacing.s2)
              : const EdgeInsets.symmetric(
                  horizontal: SoliplexSpacing.s5, vertical: SoliplexSpacing.s1),
          decoration: BoxDecoration(
            color: isUser
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                : theme.colorScheme.surface,
          ),
          child: isUser
              ? SelectableText(
                  message.text,
                  style: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                )
              : message.text.isEmpty
                  ? const Text('...')
                  : FlutterMarkdownPlusRenderer(data: message.text),
        ),
        const SizedBox(height: SoliplexSpacing.s2),
        Row(
          children: [
            CopyButton(text: message.text),
            if (isUser && onInspect != null) ...[
              const SizedBox(width: SoliplexSpacing.s2),
              Tooltip(
                message: 'Inspect HTTP traffic',
                child: InkWell(
                  onTap: onInspect,
                  borderRadius: BorderRadius.circular(4),
                  child: Icon(
                    Icons.bug_report_outlined,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            if (showFeedback) ...[
              const SizedBox(width: SoliplexSpacing.s2),
              FeedbackButtons(onFeedbackSubmit: onFeedbackSubmit!),
            ],
          ],
        ),
        if (sourceReferences != null && sourceReferences!.isNotEmpty)
          CitationsSection(
            sourceReferences: sourceReferences!,
            onShowChunkVisualization: onShowChunkVisualization,
          ),
      ],
    );
  }
}

class _ThinkingBlock extends ConsumerWidget {
  const _ThinkingBlock({
    required this.roomId,
    required this.messageId,
    required this.text,
  });

  final String roomId;
  final String messageId;
  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final expansion =
        ref.read(messageExpansionsProvider).forMessage(roomId, messageId);
    // ExpansionTile reads initiallyExpanded once on mount and does not
    // rebuild when the store changes. Safe because _ThinkingBlock and
    // ExecutionThinkingBlock are selected by hasTracker and are therefore
    // mutually exclusive for any given (roomId, messageId), so only one
    // of them writes thinkingExpanded.
    return ExpansionTile(
      initiallyExpanded: expansion.thinkingExpanded,
      onExpansionChanged: (v) => expansion.thinkingExpanded = v,
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
      childrenPadding: const EdgeInsets.only(bottom: SoliplexSpacing.s1),
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
