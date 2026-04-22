import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import '../execution_tracker.dart';
import 'error_message_tile.dart';
import 'gen_ui_tile.dart';
import 'loading_message_tile.dart';
import 'text_message_tile.dart';
import 'tool_call_tile.dart';

class MessageTile extends StatelessWidget {
  const MessageTile({
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
  final ChatMessage message;
  final String? runId;
  final List<SourceReference>? sourceReferences;
  final void Function(String runId, FeedbackType feedback, String? reason)?
      onFeedbackSubmit;
  final void Function(String runId)? onInspect;
  final void Function(SourceReference)? onShowChunkVisualization;
  final ExecutionTracker? executionTracker;
  final ActivityType? streamingActivity;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: switch (message) {
        final TextMessage m => TextMessageTile(
            roomId: roomId,
            message: m,
            runId: runId,
            sourceReferences: sourceReferences,
            onFeedbackSubmit: onFeedbackSubmit != null && runId != null
                ? (feedback, reason) =>
                    onFeedbackSubmit!(runId!, feedback, reason)
                : null,
            onInspect: onInspect != null && runId != null
                ? () => onInspect!(runId!)
                : null,
            onShowChunkVisualization: onShowChunkVisualization,
            executionTracker: executionTracker,
            streamingActivity: streamingActivity,
          ),
        final ToolCallMessage m => ToolCallTile(message: m),
        final ErrorMessage m => ErrorMessageTile(message: m),
        final GenUiMessage m => GenUiTile(message: m),
        final LoadingMessage m => LoadingMessageTile(
            roomId: roomId,
            messageId: m.id,
            executionTracker: executionTracker,
            streamingActivity: streamingActivity,
          ),
      },
    );
  }
}
