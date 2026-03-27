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
    required this.message,
    this.runId,
    this.onFeedbackSubmit,
    this.executionTracker,
    this.streamingActivity,
  });

  final ChatMessage message;
  final String? runId;
  final void Function(String runId, FeedbackType feedback, String? reason)?
      onFeedbackSubmit;
  final ExecutionTracker? executionTracker;
  final ActivityType? streamingActivity;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: switch (message) {
        final TextMessage m => TextMessageTile(
            message: m,
            runId: runId,
            onFeedbackSubmit: onFeedbackSubmit != null && runId != null
                ? (feedback, reason) =>
                    onFeedbackSubmit!(runId!, feedback, reason)
                : null,
            executionTracker: executionTracker,
            streamingActivity: streamingActivity,
          ),
        final ToolCallMessage m => ToolCallTile(message: m),
        final ErrorMessage m => ErrorMessageTile(message: m),
        final GenUiMessage m => GenUiTile(message: m),
        LoadingMessage() => LoadingMessageTile(
            executionTracker: executionTracker,
            streamingActivity: streamingActivity,
          ),
      },
    );
  }
}
