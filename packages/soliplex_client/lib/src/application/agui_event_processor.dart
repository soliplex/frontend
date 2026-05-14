import 'package:ag_ui/ag_ui.dart';
import 'package:meta/meta.dart';
import 'package:soliplex_client/src/application/activity_events.dart';
import 'package:soliplex_client/src/application/json_patch.dart';
import 'package:soliplex_client/src/application/no_response_synthesis.dart';
import 'package:soliplex_client/src/application/run_phase.dart';
import 'package:soliplex_client/src/application/streaming_state.dart';
import 'package:soliplex_client/src/domain/chat_message.dart';
import 'package:soliplex_client/src/domain/conversation.dart';
import 'package:soliplex_client/src/domain/skill_tool_call_activity.dart'
    show kSkillToolCallActivityType, kSkillToolCallActivityTypes;
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex_client.event_processor');

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
    RunFinishedEvent(:final runId) =>
      _processRunFinished(conversation, streaming, runId),
    RunErrorEvent(:final message) =>
      _processRunError(conversation, streaming, message),

    // Thinking / reasoning lifecycle — outer (Thinking/ReasoningStart/End),
    // inner thinking (ThinkingTextMessageStart/End), and reasoning message
    // (ReasoningMessageStart/Content/End) all route through the same
    // idempotent handlers.
    ThinkingStartEvent() ||
    ReasoningStartEvent() ||
    ThinkingTextMessageStartEvent() ||
    ReasoningMessageStartEvent() =>
      _processThinkingStart(
        conversation,
        streaming,
      ),
    ThinkingEndEvent() ||
    ReasoningEndEvent() ||
    ThinkingTextMessageEndEvent() ||
    ReasoningMessageEndEvent() =>
      _processThinkingEnd(conversation, streaming),
    ThinkingTextMessageContentEvent(:final delta) ||
    ReasoningMessageContentEvent(
      :final delta,
    ) =>
      _processThinkingContent(conversation, streaming, delta),

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
        streaming: _withToolCallPhase(
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
    StateSnapshotEvent(:final snapshot) =>
      _processStateSnapshot(conversation, streaming, snapshot),
    StateDeltaEvent(:final delta) => _processStateDelta(
        conversation,
        streaming,
        delta,
      ),

    // Activity snapshot events
    ActivitySnapshotEvent() =>
      _processActivitySnapshot(conversation, streaming, event),

    // Opaque provider-signed blob anchoring a reasoning message to the LLM
    // provider on follow-up turns. Round-trip preservation requires an
    // encryptedValue field on TextMessage (and on ag_ui's Message). See
    // github.com/soliplex/frontend/issues/117.
    ReasoningEncryptedValueEvent(:final entityId) =>
      _processReasoningEncryptedValue(conversation, streaming, entityId),

    // JSON Patch against the prior ActivitySnapshot's content,
    // mirroring how StateDeltaEvent patches aguiState.
    ActivityDeltaEvent() =>
      _processActivityDelta(conversation, streaming, event),

    // Unhandled event types — pass through unchanged.
    // Explicit cases ensure a compile error if ag_ui adds new event types.
    ThinkingContentEvent() ||
    TextMessageChunkEvent() ||
    ToolCallChunkEvent() ||
    MessagesSnapshotEvent() ||
    StepStartedEvent() ||
    StepFinishedEvent() ||
    RawEvent() ||
    CustomEvent() ||
    ReasoningMessageChunkEvent() =>
      EventProcessingResult(
        conversation: conversation,
        streaming: streaming,
      ),
  };
}

EventProcessingResult _processThinkingStart(
  Conversation conversation,
  StreamingState streaming,
) {
  if (streaming is AwaitingText) {
    return EventProcessingResult(
      conversation: conversation,
      streaming: streaming.copyWith(
        isThinkingStreaming: true,
        currentPhase: const ThinkingPhase(),
      ),
    );
  }
  if (streaming is TextStreaming) {
    return EventProcessingResult(
      conversation: conversation,
      streaming: streaming.copyWith(
        isThinkingStreaming: true,
        currentPhase: const ThinkingPhase(),
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

/// Events for a stale or already-closed stream are ignored.
EventProcessingResult _onActiveTextStream(
  Conversation conversation,
  StreamingState streaming,
  String messageId,
  EventProcessingResult Function(TextStreaming active) onMatch,
) {
  if (streaming is TextStreaming && streaming.messageId == messageId) {
    return onMatch(streaming);
  }
  return EventProcessingResult(
    conversation: conversation,
    streaming: streaming,
  );
}

EventProcessingResult _processTextContent(
  Conversation conversation,
  StreamingState streaming,
  String messageId,
  String delta,
) =>
    _onActiveTextStream(
      conversation,
      streaming,
      messageId,
      (active) => EventProcessingResult(
        conversation: conversation,
        streaming: active.appendDelta(delta),
      ),
    );

EventProcessingResult _processTextEnd(
  Conversation conversation,
  StreamingState streaming,
  String messageId,
) =>
    _onActiveTextStream(
      conversation,
      streaming,
      messageId,
      (active) {
        // Skip if a message with this ID already exists — idempotency guard
        // against duplicate events (e.g. from history replay).
        if (conversation.messages.any((m) => m.id == messageId)) {
          _logger.info(
            'Skipped duplicate message ID',
            attributes: {'messageId': messageId},
          );
          return EventProcessingResult(
            conversation: conversation,
            streaming: const AwaitingText(),
          );
        }

        final newMessage = TextMessage.create(
          id: messageId,
          user: active.user,
          text: active.text,
          thinkingText: active.thinkingText,
        );

        return EventProcessingResult(
          conversation: conversation.withAppendedMessage(newMessage),
          streaming: const AwaitingText(),
        );
      },
    );

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
  if (!conversation.toolCalls.any((tc) => tc.id == toolCallId)) {
    _logger.warning(
      'ToolCallArgsEvent for unknown toolCallId; delta dropped',
      attributes: {'toolCallId': toolCallId, 'deltaChars': delta.length},
    );
  }
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
  // Streaming phase is owned by phase-start handlers; ToolCallEnd leaves
  // it untouched so the current phase persists until the next one starts.
  if (!conversation.toolCalls.any((tc) => tc.id == toolCallId)) {
    _logger.warning(
      'ToolCallEndEvent for unknown toolCallId; ignored',
      attributes: {'toolCallId': toolCallId},
    );
  }
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
  ActivitySnapshotEvent event,
) {
  final updatedActivities = applyActivityEvent(
    conversation.activities,
    event,
    logger: _logger,
  );
  final updatedConversation =
      identical(updatedActivities, conversation.activities)
          ? conversation
          : conversation.copyWith(activities: updatedActivities);

  if (event.activityType == kSkillToolCallActivityType) {
    final toolName = event.content['tool_name'];
    // Pass through if tool_name is missing or not a String — the backend
    // contract requires it, so this guards against schema drift.
    if (toolName is! String) {
      _logger.warning(
        'ActivitySnapshotEvent "skill_tool_call" missing or invalid tool_name',
        attributes: {'toolNameType': toolName.runtimeType.toString()},
      );
      return EventProcessingResult(
        conversation: updatedConversation,
        streaming: streaming,
      );
    }
    return EventProcessingResult(
      conversation: updatedConversation,
      streaming: _withToolCallPhase(
        streaming,
        toolName,
        timestamp: event.timestamp,
      ),
    );
  }
  // skill_tool_result is recognized but intentionally leaves the
  // streaming phase untouched (the call phase already set it). Genuinely
  // unrecognized activityTypes still get persisted into the conversation
  // and get a breadcrumb so future decoder additions are discoverable.
  if (!kSkillToolCallActivityTypes.contains(event.activityType)) {
    _logger.info(
      'ActivitySnapshotEvent: activityType has no decoder; '
      'persisted to conversation.activities only',
      attributes: {'activityType': event.activityType},
    );
  }
  return EventProcessingResult(
    conversation: updatedConversation,
    streaming: streaming,
  );
}

/// Returns [streaming] with [toolName] accumulated on its [ToolCallPhase].
StreamingState _withToolCallPhase(
  StreamingState streaming,
  String toolName, {
  String? latestToolCallId,
  int? timestamp,
}) {
  final currentPhase = switch (streaming) {
    AwaitingText(:final currentPhase) => currentPhase,
    TextStreaming(:final currentPhase) => currentPhase,
  };

  final newPhase = switch (currentPhase) {
    ToolCallPhase() => currentPhase.withToolName(
        toolName,
        latestToolCallId: latestToolCallId,
        timestamp: timestamp,
      ),
    // Synthesize wall-clock when constructing a fresh ToolCallPhase
    // and the backend omitted a timestamp. Mirrors the same fallback
    // applied to ActivityRecord timestamps in `applyActivityEvent`.
    _ => ToolCallPhase.single(
        toolName: toolName,
        latestToolCallId: latestToolCallId,
        timestamp: timestamp ?? DateTime.now().millisecondsSinceEpoch,
      ),
  };

  return switch (streaming) {
    AwaitingText() => streaming.copyWith(currentPhase: newPhase),
    TextStreaming() => streaming.copyWith(currentPhase: newPhase),
  };
}

/// Handles `RunFinishedEvent`.
///
/// Only processes when status is `Running`; duplicate or out-of-order
/// terminal events from the backend on a non-`Running` status are ignored
/// to avoid double-appending a no-response tile (which would collide on
/// `noResponseMessageId(runId)`) or overwriting a prior terminal status.
///
/// On the `Running` path: commits any in-flight `TextStreaming` reply as
/// a finalized `TextMessage` (so a user reading half-streamed text keeps
/// it), then routes through `synthesizeFinishedNoResponse` to surface the
/// run's buffered thinking, if any, as a [NoResponseTile].
EventProcessingResult _processRunFinished(
  Conversation conversation,
  StreamingState streaming,
  String runId,
) {
  if (conversation.status is! Running) {
    _logger.warning(
      'RunFinishedEvent on non-Running status; preserving prior status. '
      'Possible cases: duplicate after terminal, or out-of-order event.',
      attributes: {
        'status': conversation.status.runtimeType.toString(),
        'runId': runId,
      },
    );
    return EventProcessingResult(
      conversation: conversation,
      streaming: streaming,
    );
  }
  final withPartial = commitPartialTextOnTerminal(
    conversation: conversation,
    streaming: streaming,
    runId: runId,
    terminalEvent: 'RunFinishedEvent',
  );
  final result = synthesizeFinishedNoResponse(
    conversation: withPartial,
    streaming: streaming,
    runId: runId,
  );
  // RunFinished with no synthesized tile and no in-flight text produces
  // no message in the list at all — `AgentSession` will return
  // `AgentSuccess(output: '')`. Surface as info so the corner case shows
  // up in BackendLogSink instead of being silent. Decline can fire for
  // empty thinking, an unresolved tool call, or both — log both counts
  // so a triage reader can tell which branch decided.
  if (!result.synthesized && streaming is! TextStreaming) {
    _logger.info(
      'RunFinishedEvent produced no NoResponseTile (synthesis declined)',
      attributes: {
        'runId': runId,
        'bufferedThinkingChars': streaming is AwaitingText
            ? streaming.bufferedThinkingText.length
            : 0,
        'unresolvedToolCallCount': conversation.toolCalls
            .where(
              (tc) =>
                  tc.status == ToolCallStatus.pending ||
                  tc.status == ToolCallStatus.streaming ||
                  tc.status == ToolCallStatus.executing,
            )
            .length,
      },
    );
  }
  return EventProcessingResult(
    conversation: result.conversation.withStatus(const Completed()),
    streaming: const AwaitingText(),
  );
}

/// Handles `RunErrorEvent` with a runId-aware no-response synthesis path.
///
/// The synthesis helper needs a runId to mint a stable message id. The
/// authoritative source for an in-flight runId is `Running` status; the
/// event itself doesn't carry one. When the conversation is in any other
/// status at the time `RunErrorEvent` arrives — `Idle` (pre-run error),
/// `Completed` / `Failed` / `Cancelled` (post-terminal duplicate or
/// out-of-order event) — synthesis is impossible without a runId, and the
/// existing terminal status must not be overwritten.
///
/// When `streaming` is `TextStreaming` (a reply was streaming when the
/// error fired), the partial text is committed as a `TextMessage` before
/// the conversation flips to `Failed` so the user keeps the half-rendered
/// reply they were already reading.
EventProcessingResult _processRunError(
  Conversation conversation,
  StreamingState streaming,
  String message,
) {
  if (conversation.status case Running(:final runId)) {
    final withPartial = commitPartialTextOnTerminal(
      conversation: conversation,
      streaming: streaming,
      runId: runId,
      terminalEvent: 'RunErrorEvent',
    );
    final result = synthesizeFailedNoResponse(
      conversation: withPartial,
      streaming: streaming,
      runId: runId,
      errorDetail: message,
    );
    // The partial-text commit already produces a user-visible signal in
    // the messages list — synthesis declines on TextStreaming by design,
    // so don't log the decline path as anomalous.
    final committedPartial = streaming is TextStreaming;
    if (!result.synthesized && !committedPartial) {
      _logger.info(
        'RunErrorEvent: NoResponseTile synthesis declined; falling back '
        'to ErrorMessage',
        attributes: {
          'runId': runId,
          'streaming': streaming.runtimeType.toString(),
          'message': message,
          'bufferedThinkingChars': streaming is AwaitingText
              ? streaming.bufferedThinkingText.length
              : 0,
          'unresolvedToolCallCount': conversation.toolCalls
              .where(
                (tc) =>
                    tc.status == ToolCallStatus.pending ||
                    tc.status == ToolCallStatus.streaming ||
                    tc.status == ToolCallStatus.executing,
              )
              .length,
        },
      );
    }
    // Append an ErrorMessage when synthesis declined so the run failure
    // has a visible status row in the messages list. With a partial
    // commit it sits alongside the half-streamed reply.
    final surfaced = result.synthesized
        ? result.conversation
        : withPartial.withAppendedMessage(
            ErrorMessage.create(
              id: runErrorMessageId(runId),
              message: message,
            ),
          );
    return EventProcessingResult(
      conversation: surfaced.withStatus(Failed(error: message)),
      streaming: const AwaitingText(),
    );
  }
  final droppedThinkingChars =
      streaming is AwaitingText ? streaming.bufferedThinkingText.length : 0;
  final logAttributes = {
    'status': conversation.status.runtimeType.toString(),
    'streaming': streaming.runtimeType.toString(),
    'message': message,
    'droppedThinkingChars': droppedThinkingChars,
  };
  if (conversation.status is Idle) {
    // RunErrorEvent without a preceding RunStartedEvent is a backend
    // protocol violation. Log at error level for backend escalation,
    // then append an ErrorMessage so the user gets a visible failure
    // row instead of a silent status-only flip.
    _logger.error(
      'RunErrorEvent on Idle: pre-run failure (backend protocol violation)',
      attributes: logAttributes,
    );
    return EventProcessingResult(
      conversation: conversation
          .withAppendedMessage(
            ErrorMessage.create(
              id: preRunErrorMessageId(conversation.threadId, message),
              message: message,
            ),
          )
          .withStatus(Failed(error: message)),
      streaming: const AwaitingText(),
    );
  }
  _logger.warning(
    'RunErrorEvent on terminal status; preserving prior status. '
    'Possible cases: duplicate after terminal, or out-of-order event.',
    attributes: logAttributes,
  );
  final nextStatus = switch (conversation.status) {
    Completed() || Failed() || Cancelled() => conversation.status,
    Idle() ||
    Running() =>
      throw StateError('Idle/Running unreachable in terminal-preserve branch'),
  };
  return EventProcessingResult(
    conversation: conversation.withStatus(nextStatus),
    streaming: const AwaitingText(),
  );
}

// State events - apply JSON Patch

EventProcessingResult _processStateSnapshot(
  Conversation conversation,
  StreamingState streaming,
  dynamic snapshot,
) {
  // The cast throws on non-Map snapshots. The per-event-loop wrappers
  // in `RunOrchestrator._onEvent` and `SoliplexApi._replayEventsToHistory`
  // catch the throw and append a `DroppedEventMessage` at the failure
  // position; surrounding events still process. Future callers of
  // `processEvent` that don't wrap inherit this contract.
  return EventProcessingResult(
    conversation:
        conversation.copyWith(aguiState: snapshot as Map<String, dynamic>),
    streaming: streaming,
  );
}

EventProcessingResult _processStateDelta(
  Conversation conversation,
  StreamingState streaming,
  List<dynamic> delta,
) {
  final newState =
      applyJsonPatch(conversation.aguiState, delta, logger: _logger);
  return EventProcessingResult(
    conversation: conversation.copyWith(aguiState: newState),
    streaming: streaming,
  );
}

// Logged pass-through for events we do not yet integrate into the domain.

EventProcessingResult _processReasoningEncryptedValue(
  Conversation conversation,
  StreamingState streaming,
  String entityId,
) {
  _logger.warning(
    'ReasoningEncryptedValueEvent dropped: round-trip preservation '
    'requires encryptedValue on TextMessage — see '
    'github.com/soliplex/frontend/issues/117',
    attributes: {'entityId': entityId},
  );
  return EventProcessingResult(
    conversation: conversation,
    streaming: streaming,
  );
}

/// Applies an [ActivityDeltaEvent] to [Conversation.activities],
/// preserving streaming state. Drop semantics (no prior snapshot,
/// activityType mismatch, malformed patch ops) live in
/// [applyActivityEvent]; this wrapper only forwards the result.
EventProcessingResult _processActivityDelta(
  Conversation conversation,
  StreamingState streaming,
  ActivityDeltaEvent event,
) {
  final updated = applyActivityEvent(
    conversation.activities,
    event,
    logger: _logger,
  );
  if (identical(updated, conversation.activities)) {
    return EventProcessingResult(
      conversation: conversation,
      streaming: streaming,
    );
  }
  return EventProcessingResult(
    conversation: conversation.copyWith(activities: updated),
    streaming: streaming,
  );
}
