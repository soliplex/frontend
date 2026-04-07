import 'dart:developer' as developer;

import 'package:ag_ui/ag_ui.dart';
import 'package:meta/meta.dart';
import 'package:soliplex_client/src/application/json_patch.dart';
import 'package:soliplex_client/src/application/streaming_state.dart';
import 'package:soliplex_client/src/domain/chat_message.dart';
import 'package:soliplex_client/src/domain/conversation.dart';

/// Result of processing an AG-UI event.
///
/// Contains both the updated domain state (Conversation) and ephemeral
/// streaming state.
@immutable
class EventProcessingResult {
  /// Creates an event processing result.
  const EventProcessingResult({
    required this.conversation,
    required this.streaming,
  });

  /// Updated conversation (domain state).
  final Conversation conversation;

  /// Updated streaming state (ephemeral operation state).
  final StreamingState streaming;
}

/// Processes a single AG-UI event, returning updated domain and streaming
/// state.
///
/// This is a pure function with no side effects. It takes the current state
/// and an event, and returns the new state.
///
/// Example usage:
/// ```dart
/// final result = processEvent(conversation, streaming, event);
/// // result.conversation - updated domain state
/// // result.streaming - updated streaming state
/// ```
EventProcessingResult processEvent(
  Conversation conversation,
  StreamingState streaming,
  BaseEvent event,
) {
  return switch (event) {
    // Run lifecycle events
    RunStartedEvent(:final runId) => EventProcessingResult(
        conversation: conversation.withStatus(Running(runId: runId)),
        streaming: streaming,
      ),
    RunFinishedEvent() => EventProcessingResult(
        conversation: conversation.withStatus(const Completed()),
        streaming: const AwaitingText(),
      ),
    RunErrorEvent(:final message) => EventProcessingResult(
        conversation: conversation.withStatus(Failed(error: message)),
        streaming: const AwaitingText(),
      ),

    // Thinking lifecycle — both outer (ThinkingStart/End) and inner
    // (ThinkingTextMessageStart/End) use the same idempotent handlers.
    ThinkingStartEvent() => _processThinkingStart(
        conversation,
        streaming,
      ),
    ThinkingEndEvent() => _processThinkingEnd(
        conversation,
        streaming,
      ),
    ThinkingTextMessageStartEvent() => _processThinkingStart(
        conversation,
        streaming,
      ),
    ThinkingTextMessageContentEvent(:final delta) => _processThinkingContent(
        conversation,
        streaming,
        delta,
      ),
    ThinkingTextMessageEndEvent() => _processThinkingEnd(
        conversation,
        streaming,
      ),

    // Text message streaming events
    TextMessageStartEvent(:final messageId, :final role) => _processTextStart(
        conversation,
        streaming,
        messageId,
        role,
      ),
    TextMessageContentEvent(:final messageId, :final delta) =>
      _processTextContent(conversation, streaming, messageId, delta),
    TextMessageEndEvent(:final messageId) => _processTextEnd(
        conversation,
        streaming,
        messageId,
      ),

    // Tool call events — accumulate tool names on start, args via deltas,
    // transition to pending on end (tool stays in conversation.toolCalls).
    ToolCallStartEvent(
      :final toolCallId,
      :final toolCallName,
      :final timestamp,
    ) =>
      EventProcessingResult(
        conversation: conversation.withToolCall(
          ToolCallInfo(
            id: toolCallId,
            name: toolCallName,
            status: ToolCallStatus.streaming,
          ),
        ),
        streaming: _withToolCallActivity(
          streaming,
          toolCallName,
          latestToolCallId: toolCallId,
          timestamp: timestamp,
        ),
      ),
    ToolCallArgsEvent(:final toolCallId, :final delta) => _processToolCallArgs(
        conversation,
        streaming,
        toolCallId,
        delta,
      ),
    ToolCallEndEvent(:final toolCallId) => _processToolCallEnd(
        conversation,
        streaming,
        toolCallId,
      ),
    ToolCallResultEvent(:final toolCallId, :final content) =>
      _processToolCallResult(conversation, streaming, toolCallId, content),

    // State events - apply to conversation.aguiState
    StateSnapshotEvent(:final snapshot) => EventProcessingResult(
        conversation: conversation.copyWith(
          aguiState: snapshot as Map<String, dynamic>,
        ),
        streaming: streaming,
      ),
    StateDeltaEvent(:final delta) => _processStateDelta(
        conversation,
        streaming,
        delta,
      ),

    // Activity snapshot events
    ActivitySnapshotEvent(
      :final activityType,
      :final content,
      :final timestamp,
    ) =>
      _processActivitySnapshot(
        conversation,
        streaming,
        activityType,
        content,
        timestamp,
      ),

    // Unhandled event types — pass through unchanged.
    // Explicit cases ensure a compile error if ag_ui adds new event types.
    ThinkingContentEvent() ||
    TextMessageChunkEvent() ||
    ToolCallChunkEvent() ||
    MessagesSnapshotEvent() ||
    StepStartedEvent() ||
    StepFinishedEvent() ||
    RawEvent() ||
    CustomEvent() =>
      EventProcessingResult(
        conversation: conversation,
        streaming: streaming,
      ),
  };
}

// Thinking events - buffer thinking text in AwaitingText state

EventProcessingResult _processThinkingStart(
  Conversation conversation,
  StreamingState streaming,
) {
  // Mark thinking as streaming and set activity
  if (streaming is AwaitingText) {
    return EventProcessingResult(
      conversation: conversation,
      streaming: streaming.copyWith(
        isThinkingStreaming: true,
        currentActivity: const ThinkingActivity(),
      ),
    );
  }
  if (streaming is TextStreaming) {
    return EventProcessingResult(
      conversation: conversation,
      streaming: streaming.copyWith(
        isThinkingStreaming: true,
        currentActivity: const ThinkingActivity(),
      ),
    );
  }
  return EventProcessingResult(
    conversation: conversation,
    streaming: streaming,
  );
}

EventProcessingResult _processThinkingContent(
  Conversation conversation,
  StreamingState streaming,
  String delta,
) {
  if (streaming is AwaitingText) {
    return EventProcessingResult(
      conversation: conversation,
      streaming: streaming.copyWith(
        bufferedThinkingText: streaming.bufferedThinkingText + delta,
      ),
    );
  }
  if (streaming is TextStreaming) {
    return EventProcessingResult(
      conversation: conversation,
      streaming: streaming.appendThinkingDelta(delta),
    );
  }
  return EventProcessingResult(
    conversation: conversation,
    streaming: streaming,
  );
}

EventProcessingResult _processThinkingEnd(
  Conversation conversation,
  StreamingState streaming,
) {
  if (streaming is AwaitingText) {
    return EventProcessingResult(
      conversation: conversation,
      streaming: streaming.copyWith(isThinkingStreaming: false),
    );
  }
  if (streaming is TextStreaming) {
    return EventProcessingResult(
      conversation: conversation,
      streaming: streaming.copyWith(isThinkingStreaming: false),
    );
  }
  return EventProcessingResult(
    conversation: conversation,
    streaming: streaming,
  );
}

EventProcessingResult _processTextStart(
  Conversation conversation,
  StreamingState streaming,
  String messageId,
  TextMessageRole role,
) {
  // Transfer any buffered thinking from AwaitingText to TextStreaming
  final thinkingText =
      streaming is AwaitingText ? streaming.bufferedThinkingText : '';
  final isThinkingStreaming =
      streaming is AwaitingText && streaming.isThinkingStreaming;

  return EventProcessingResult(
    conversation: conversation,
    streaming: TextStreaming(
      messageId: messageId,
      user: _mapRoleToChatUser(role),
      text: '',
      thinkingText: thinkingText,
      isThinkingStreaming: isThinkingStreaming,
    ),
  );
}

// TODO(cleanup): Extract streaming guard pattern if a third streaming event
// type is added. Both _processTextContent and _processTextEnd share the
// "check if streaming matches messageId, else return unchanged" pattern.
EventProcessingResult _processTextContent(
  Conversation conversation,
  StreamingState streaming,
  String messageId,
  String delta,
) {
  if (streaming is TextStreaming && streaming.messageId == messageId) {
    return EventProcessingResult(
      conversation: conversation,
      streaming: streaming.appendDelta(delta),
    );
  }
  return EventProcessingResult(
    conversation: conversation,
    streaming: streaming,
  );
}

EventProcessingResult _processTextEnd(
  Conversation conversation,
  StreamingState streaming,
  String messageId,
) {
  if (streaming is TextStreaming && streaming.messageId == messageId) {
    // Skip if a message with this ID already exists — idempotency guard
    // against duplicate events (e.g. from history replay).
    if (conversation.messages.any((m) => m.id == messageId)) {
      developer.log(
        'Skipped duplicate message ID: $messageId',
        name: 'soliplex_client.event_processor',
        level: 800,
      );
      return EventProcessingResult(
        conversation: conversation,
        streaming: const AwaitingText(),
      );
    }

    final newMessage = TextMessage.create(
      id: messageId,
      user: streaming.user,
      text: streaming.text,
      thinkingText: streaming.thinkingText,
    );

    return EventProcessingResult(
      conversation: conversation.withAppendedMessage(newMessage),
      streaming: const AwaitingText(),
    );
  }
  return EventProcessingResult(
    conversation: conversation,
    streaming: streaming,
  );
}

/// Maps AG-UI TextMessageRole to domain ChatUser.
ChatUser _mapRoleToChatUser(TextMessageRole role) {
  return switch (role) {
    TextMessageRole.user => ChatUser.user,
    TextMessageRole.assistant => ChatUser.assistant,
    TextMessageRole.system => ChatUser.system,
    TextMessageRole.developer => ChatUser.system,
  };
}

// Tool call events — args accumulation and end transition

EventProcessingResult _processToolCallArgs(
  Conversation conversation,
  StreamingState streaming,
  String toolCallId,
  String delta,
) {
  // Only accumulate args while the tool call is still streaming.
  // Late deltas after ToolCallEnd are ignored to prevent mutation of
  // finalized arguments.
  final updatedToolCalls = conversation.toolCalls.map((tc) {
    if (tc.id == toolCallId && tc.status == ToolCallStatus.streaming) {
      return tc.copyWith(arguments: tc.arguments + delta);
    }
    return tc;
  }).toList();

  return EventProcessingResult(
    conversation: conversation.copyWith(toolCalls: updatedToolCalls),
    streaming: streaming,
  );
}

EventProcessingResult _processToolCallEnd(
  Conversation conversation,
  StreamingState streaming,
  String toolCallId,
) {
  // Only transition streaming → pending. Guard prevents downgrading tools
  // that are already executing/completed/failed (e.g. duplicate ToolCallEnd).
  // Keep the tool in conversation.toolCalls (execution happens in Slice 3).
  // Activity persists until the next activity starts — don't change it here.
  final updatedToolCalls = conversation.toolCalls.map((tc) {
    if (tc.id == toolCallId && tc.status == ToolCallStatus.streaming) {
      return tc.copyWith(status: ToolCallStatus.pending);
    }
    return tc;
  }).toList();

  return EventProcessingResult(
    conversation: conversation.copyWith(toolCalls: updatedToolCalls),
    streaming: streaming,
  );
}

EventProcessingResult _processToolCallResult(
  Conversation conversation,
  StreamingState streaming,
  String toolCallId,
  String content,
) {
  final updatedToolCalls = conversation.toolCalls.map((tc) {
    if (tc.id == toolCallId &&
        (tc.status == ToolCallStatus.pending ||
            tc.status == ToolCallStatus.streaming)) {
      return tc.copyWith(status: ToolCallStatus.completed, result: content);
    }
    return tc;
  }).toList();

  return EventProcessingResult(
    conversation: conversation.copyWith(toolCalls: updatedToolCalls),
    streaming: streaming,
  );
}

// Activity snapshot events

EventProcessingResult _processActivitySnapshot(
  Conversation conversation,
  StreamingState streaming,
  String activityType,
  Map<String, dynamic> content,
  int? timestamp,
) {
  if (activityType == 'skill_tool_call') {
    final toolName = content['tool_name'];
    // Pass through if tool_name is missing or not a String — the backend
    // contract requires it, so this guards against schema drift.
    if (toolName is! String) {
      developer.log(
        'ActivitySnapshotEvent "skill_tool_call" missing or invalid '
        'tool_name: ${toolName.runtimeType}',
        name: 'soliplex_client.event_processor',
        level: 900,
      );
      return EventProcessingResult(
        conversation: conversation,
        streaming: streaming,
      );
    }
    return EventProcessingResult(
      conversation: conversation,
      streaming: _withToolCallActivity(
        streaming,
        toolName,
        timestamp: timestamp ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }
  // Unknown activity types pass through unchanged.
  developer.log(
    'Unhandled activityType: $activityType',
    name: 'soliplex_client.event_processor',
    level: 800,
  );
  return EventProcessingResult(
    conversation: conversation,
    streaming: streaming,
  );
}

// Tool call activity helper

/// Returns [streaming] with [toolName] accumulated on its [ToolCallActivity].
StreamingState _withToolCallActivity(
  StreamingState streaming,
  String toolName, {
  String? latestToolCallId,
  int? timestamp,
}) {
  final currentActivity = switch (streaming) {
    AwaitingText(:final currentActivity) => currentActivity,
    TextStreaming(:final currentActivity) => currentActivity,
  };

  final newActivity = switch (currentActivity) {
    ToolCallActivity() => currentActivity.withToolName(
        toolName,
        latestToolCallId: latestToolCallId,
        timestamp: timestamp,
      ),
    _ => ToolCallActivity(
        toolName: toolName,
        latestToolCallId: latestToolCallId,
        timestamp: timestamp,
      ),
  };

  return switch (streaming) {
    AwaitingText() => streaming.copyWith(currentActivity: newActivity),
    TextStreaming() => streaming.copyWith(currentActivity: newActivity),
  };
}

// State events - apply JSON Patch

EventProcessingResult _processStateDelta(
  Conversation conversation,
  StreamingState streaming,
  List<dynamic> delta,
) {
  final newState = applyJsonPatch(conversation.aguiState, delta);
  return EventProcessingResult(
    conversation: conversation.copyWith(aguiState: newState),
    streaming: streaming,
  );
}
