import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import '../execution_tracker.dart';
import 'citations_section.dart';
import 'copy_button.dart';
import 'execution/phase_indicator.dart';
import 'execution/execution_timeline.dart';
import 'execution/static_thinking_block.dart';
import 'execution/thinking_block.dart';
import 'feedback_buttons.dart';
import 'markdown/flutter_markdown_plus_renderer.dart';
import 'workdir_files_section.dart';
import '../../../design/design.dart';

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
    this.onFetchWorkdirFiles,
    this.onDownloadWorkdirFile,
    this.onPreviewWorkdirFile,
    this.executionTracker,
    this.streamingPhase,
  });

  final String roomId;
  final TextMessage message;
  final String? runId;
  final List<SourceReference>? sourceReferences;
  final void Function(FeedbackType feedback, String? reason)? onFeedbackSubmit;
  final VoidCallback? onInspect;
  final void Function(SourceReference)? onShowChunkVisualization;
  final FetchWorkdirFiles? onFetchWorkdirFiles;
  final DownloadWorkdirFile? onDownloadWorkdirFile;
  final FetchWorkdirFileBytes? onPreviewWorkdirFile;
  final ExecutionTracker? executionTracker;
  final RunPhase? streamingPhase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.user == ChatUser.user;
    final showFeedback = !isUser && onFeedbackSubmit != null;
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
        else if (!isUser && message.hasThinkingText)
          StaticThinkingBlock(
            roomId: roomId,
            messageId: message.id,
            text: message.thinkingText,
          ),
        Text(
          isUser ? 'You' : 'Assistant',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: SoliplexSpacing.s1),
        _MessageBubble(message: message),
        const SizedBox(height: SoliplexSpacing.s1),
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
        if (!isUser &&
            runId != null &&
            onFetchWorkdirFiles != null &&
            onDownloadWorkdirFile != null)
          WorkdirFilesSection(
            // Force re-mount (and re-fetch) if the assistant message is
            // ever rebuilt with a different runId.
            key: ValueKey(runId),
            runId: runId!,
            fetchFiles: onFetchWorkdirFiles!,
            onDownload: onDownloadWorkdirFile!,
            onPreview: onPreviewWorkdirFile,
          ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final TextMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.user == ChatUser.user;

    return Container(
      // design-system exception: 14/10 is the documented chat-bubble padding
      // (see design_handoff/handoff/README.md "the only 14 in the system").
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isUser
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(soliplexRadii.md),
      ),
      child: isUser
          ? SelectableText(
              message.text,
              style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
            )
          : message.text.isEmpty
              ? const Text('...')
              : FlutterMarkdownPlusRenderer(data: message.text),
    );
  }
}
