import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import '../execution_tracker.dart';
import 'citations_section.dart';
import 'dropped_event_message_tile.dart';
import 'error_message_tile.dart';
import 'gen_ui_tile.dart';
import 'loading_message_tile.dart';
import 'no_response_tile_widget.dart';
import 'text_message_tile.dart';
import 'tool_call_tile.dart';
import 'workdir_files_section.dart';
import 'package:soliplex_design/soliplex_design.dart';

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
    this.onFetchPicture,
    this.onFetchWorkdirFiles,
    this.onDownloadWorkdirFile,
    this.onPreviewWorkdirFile,
    this.executionTracker,
    this.streamingPhase,
  });

  final String roomId;
  final ChatMessage message;
  final String? runId;
  final List<SourceReference>? sourceReferences;
  final void Function(String runId, FeedbackType feedback, String? reason)?
      onFeedbackSubmit;
  final void Function(String runId)? onInspect;
  final void Function(SourceReference)? onShowChunkVisualization;
  final PictureFetcher? onFetchPicture;
  final FetchWorkdirFiles? onFetchWorkdirFiles;
  final DownloadWorkdirFile? onDownloadWorkdirFile;
  final FetchWorkdirFileBytes? onPreviewWorkdirFile;
  final ExecutionTracker? executionTracker;
  final RunPhase? streamingPhase;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
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
            onFetchPicture: onFetchPicture,
            onFetchWorkdirFiles: onFetchWorkdirFiles,
            onDownloadWorkdirFile: onDownloadWorkdirFile,
            onPreviewWorkdirFile: onPreviewWorkdirFile,
            executionTracker: executionTracker,
            streamingPhase: streamingPhase,
          ),
        final NoResponseTile m => NoResponseTileWidget(
            roomId: roomId,
            message: m,
            executionTracker: executionTracker,
            streamingPhase: streamingPhase,
          ),
        final ToolCallMessage m => ToolCallTile(message: m),
        final ErrorMessage m => ErrorMessageTile(message: m),
        final GenUiMessage m => GenUiTile(message: m),
        final LoadingMessage m => LoadingMessageTile(
            roomId: roomId,
            messageId: m.id,
            executionTracker: executionTracker,
            streamingPhase: streamingPhase,
          ),
        final DroppedEventMessage m => DroppedEventMessageTile(message: m),
      },
    );
  }
}
