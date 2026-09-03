// Four upstream types are deprecated, scheduled for removal in ag_ui 1.0.0:
// THINKING_TEXT_MESSAGE_{START,CONTENT,END} and THINKING_CONTENT.
// `ThinkingStartEvent` and `ThinkingEndEvent` are NOT deprecated and their arms
// stay regardless — a removal sweep grepping "THINKING" must not touch them.
// The THINKING_TEXT_MESSAGE_* arms stay because stored threads still decode to
// them; the THINKING_CONTENT arm stays only to keep `processEvent`'s switch
// over sealed `BaseEvent` exhaustive (upstream documents it as Dart-only legacy
// that was never part of the canonical protocol). Suppressed per line so the
// 1.0.0 sweep can enumerate them and an unrelated deprecation here still
// raises.

import 'package:ag_ui/ag_ui.dart';
import 'package:meta/meta.dart';
import 'package:soliplex_client/src/application/activity_events.dart';
import 'package:soliplex_client/src/application/json_patch.dart';
import 'package:soliplex_client/src/application/no_response_synthesis.dart';
import 'package:soliplex_client/src/application/run_phase.dart';
import 'package:soliplex_client/src/application/streaming_state.dart';
import 'package:soliplex_client/src/domain/chat_message.dart';
import 'package:soliplex_client/src/domain/conversation.dart';
import 'package:soliplex_client/src/errors/exceptions.dart';
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
/// A minted message's `createdAt` resolves to `event.timestamp ?? runCreated`,
/// where [runCreated] is the run's server `created` (supplied during replay,
/// null while live). Both may be null — the message then carries no timestamp
/// rather than a client-generated one.
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
  BaseEvent event, {
  DateTime? runCreated,
}) {
  return switch (event) {
    // Run lifecycle events
    RunStartedEvent(:final runId) => EventProcessingResult(
        conversation: conversation.withStatus(Running(runId: runId)),
        streaming: streaming,
      ),
    RunFinishedEvent(:final runId, :final timestamp) => _processRunFinished(
        conversation,
        streaming,
        runId,
        createdAt: _eventTime(timestamp) ?? runCreated,
      ),
    RunErrorEvent(:final message, :final timestamp) => _processRunError(
        conversation,
        streaming,
        message,
        createdAt: _eventTime(timestamp) ?? runCreated,
      ),

    // Thinking / reasoning lifecycle — outer (Thinking/ReasoningStart/End),
    // inner thinking (ThinkingTextMessageStart/End), and reasoning message
    // (ReasoningMessageStart/Content/End) all route through the same
    // idempotent handlers.
    ThinkingStartEvent() ||
    ReasoningStartEvent() ||
    // Deprecated upstream; retained to decode stored threads.
    // ignore: deprecated_member_use
    ThinkingTextMessageStartEvent() ||
    ReasoningMessageStartEvent() =>
      _processThinkingStart(
        conversation,
        streaming,
      ),
    ThinkingEndEvent() ||
    ReasoningEndEvent() ||
    // Deprecated upstream; retained to decode stored threads.
    // ignore: deprecated_member_use
    ThinkingTextMessageEndEvent() ||
    ReasoningMessageEndEvent() =>
      _processThinkingEnd(conversation, streaming),
    // Deprecated upstream; retained to decode stored threads.
    // ignore: deprecated_member_use
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
    TextMessageEndEvent(:final messageId, :final timestamp) => _processTextEnd(
        conversation,
        streaming,
        messageId,
        createdAt: _eventTime(timestamp) ?? runCreated,
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
    MessagesSnapshotEvent(:final messages) =>
      _processMessagesSnapshot(conversation, streaming, messages),

    // Unhandled event types — pass through unchanged.
    // Explicit cases ensure a compile error if ag_ui adds new event types.
    // Deprecated upstream; arm only keeps the sealed switch exhaustive.
    // ignore: deprecated_member_use
    ThinkingContentEvent() ||
    TextMessageChunkEvent() ||
    ToolCallChunkEvent() ||
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

/// Passes the snapshot through unreconciled.
///
/// AG-UI treats `MESSAGES_SNAPSHOT` as the authoritative message list, but this
/// client does not rebuild `conversation.messages` from it, so a server-side
/// prune or rewrite of history diverges here. Logged rather than surfaced as a
/// drop tile: a producer that emits snapshots routinely would mint a tile on
/// every run.
EventProcessingResult _processMessagesSnapshot(
  Conversation conversation,
  StreamingState streaming,
  List<Message> messages,
) {
  _logger.warning(
    'MessagesSnapshotEvent received but not reconciled against '
    'conversation.messages; client may now hold a divergent history '
    '(snapshot: ${messages.length} messages, local: '
    '${conversation.messages.length})',
    attributes: {
      'snapshotMessageCount': messages.length,
      'localMessageCount': conversation.messages.length,
    },
  );
  return EventProcessingResult(
    conversation: conversation,
    streaming: streaming,
  );
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

/// Converts an AG-UI event's epoch-millisecond [timestamp] to a UTC [DateTime],
/// or null when the event carries no timestamp.
DateTime? _eventTime(int? timestamp) => timestamp == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true);

EventProcessingResult _processTextEnd(
  Conversation conversation,
  StreamingState streaming,
  String messageId, {
  DateTime? createdAt,
}) =>
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
          createdAt: createdAt,
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
  // `content` is `Object?` upstream, but `ActivityRecord.content` is a
  // `Map<String, dynamic>`, so a non-object payload has nowhere to go. Thrown
  // so the caller mints a drop tile, which is the only thing on screen saying
  // the event arrived at all. It does not settle the row the event belonged to:
  // a dropped snapshot leaves the record at whatever a prior one stored, and
  // nothing later rewrites it.
  final content = event.content;
  if (content is! Map<String, dynamic>) {
    throw MalformedResponseException(
      message: 'ActivitySnapshotEvent content must be a JSON object, got '
          '${content.runtimeType} (messageId: ${event.messageId}, '
          'activityType: ${event.activityType})',
    );
  }

  final updatedActivities = applyActivityEvent(
    conversation.activities,
    event,
    logger: _logger,
  );
  final updatedConversation =
      identical(updatedActivities, conversation.activities)
          ? conversation
          : conversation.copyWith(activities: updatedActivities);

  // The streaming phase label is set by `TOOL_CALL_START`, not from here.
  // Content is opaque under AG-UI, so this layer must not attribute a phase
  // from it even when a `tool_name` is present — announcing a tool call from a
  // payload the protocol says nothing about would put a phase on screen for a
  // tool the run may never make.
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
    // Fresh-construction branch only: synthesize wall-clock when the
    // backend omitted a timestamp. The accumulation branch above
    // deliberately inherits the prior phase's timestamp via
    // `withToolName`'s `timestamp ?? this.timestamp` — re-synthesizing
    // there would bump the phase's hashCode on every tool event and
    // break `identical()` short-circuits downstream. Mirrors the
    // same fresh-record fallback in `applyActivityEvent`.
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
  String runId, {
  DateTime? createdAt,
}) {
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
    createdAt: createdAt,
  );
  final result = synthesizeFinishedNoResponse(
    conversation: withPartial,
    streaming: streaming,
    runId: runId,
    createdAt: createdAt,
  );
  // RunFinished with no synthesized tile and no reply open produces no
  // message in the list at all — `AgentSession` will return
  // `AgentSuccess(output: '')`. Surface as info so the corner case shows
  // up in BackendLogSink instead of being silent. A reply that was open but
  // held nothing also produces no message; `commitPartialTextOnTerminal`
  // records that one, so it is not reported twice here. Decline can fire for
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
  String message, {
  DateTime? createdAt,
}) {
  if (conversation.status case Running(:final runId)) {
    final withPartial = commitPartialTextOnTerminal(
      conversation: conversation,
      streaming: streaming,
      runId: runId,
      terminalEvent: 'RunErrorEvent',
      createdAt: createdAt,
    );
    final result = synthesizeFailedNoResponse(
      conversation: withPartial,
      streaming: streaming,
      runId: runId,
      errorDetail: message,
      createdAt: createdAt,
    );
    // A reply was open when the error arrived: synthesis declines on
    // TextStreaming by design, and the ErrorMessage appended below carries
    // the failure whether or not that reply had anything to commit, so this
    // is not the anomalous decline the log is for.
    final replyWasOpen = streaming is TextStreaming;
    if (!result.synthesized && !replyWasOpen) {
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
              createdAt: createdAt,
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
              createdAt: createdAt,
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
