import 'package:ag_ui/ag_ui.dart';
import 'package:soliplex_client/src/application/json_patch.dart';
import 'package:soliplex_client/src/domain/transcript.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex_client.transcript');

/// Folds one AG-UI [event] into [transcript], building the history to send as
/// the backend's own client (`soliplex.agui.parser.EventStreamParser`) does,
/// except that:
/// - a call naming no parent joins the last message when that is an
///   assistant message, else one opened for it;
/// - an encrypted value travels with the tool call or result it names;
/// - a call takes one result;
/// - a messages snapshot is ignored;
/// - an activity delta using `move`, `copy` or `test` is skipped, as those
///   operations are not applied here.
///
/// Where that parser raises, this logs without the event's content and
/// carries on, so one bad event does not cost the thread its history. Such an
/// event changes nothing, except that a repeated start replaces the open call
/// and an end whose parent is not an assistant message closes the call
/// unsent.
Transcript applyTranscriptEvent(Transcript transcript, BaseEvent event) {
  return switch (event) {
    TextMessageStartEvent(:final messageId) =>
      _startText(transcript, messageId),
    TextMessageContentEvent(:final messageId, :final delta) =>
      _appendText(transcript, messageId, delta),
    ToolCallStartEvent(
      :final toolCallId,
      :final toolCallName,
      :final parentMessageId,
    ) =>
      _startToolCall(
        transcript,
        toolCallId,
        toolCallName,
        parentMessageId,
      ),
    ToolCallArgsEvent(:final toolCallId, :final delta) =>
      _appendToolCallArgs(transcript, toolCallId, delta),
    ToolCallEndEvent(:final toolCallId) => _endToolCall(transcript, toolCallId),
    ToolCallResultEvent(:final messageId, :final toolCallId, :final content) =>
      appendToolResult(
        transcript,
        ToolMessage(id: messageId, toolCallId: toolCallId, content: content),
      ),
    ReasoningEncryptedValueEvent() => _setEncryptedValue(transcript, event),
    ActivitySnapshotEvent() => _applyActivitySnapshot(transcript, event),
    ActivityDeltaEvent() => _applyActivityDelta(transcript, event),
    // Listed so a new event type is a compile error here. Nothing in these
    // reaches the history: lifecycle, state, steps, raw and custom events,
    // reasoning (whose round trip is github.com/soliplex/frontend/issues/117),
    // chunk events no supported backend sends, and a messages snapshot, which
    // nothing emits and which would let the history shrink.
    TextMessageEndEvent() ||
    RunStartedEvent() ||
    RunFinishedEvent() ||
    RunErrorEvent() ||
    StepStartedEvent() ||
    StepFinishedEvent() ||
    StateSnapshotEvent() ||
    StateDeltaEvent() ||
    MessagesSnapshotEvent() ||
    RawEvent() ||
    CustomEvent() ||
    TextMessageChunkEvent() ||
    ToolCallChunkEvent() ||
    ReasoningStartEvent() ||
    ReasoningEndEvent() ||
    ReasoningMessageStartEvent() ||
    ReasoningMessageContentEvent() ||
    ReasoningMessageEndEvent() ||
    ReasoningMessageChunkEvent() ||
    ThinkingStartEvent() ||
    ThinkingEndEvent() ||
    // Deprecated upstream; see agui_event_processor.dart's header.
    // ignore: deprecated_member_use
    ThinkingTextMessageStartEvent() ||
    // Deprecated upstream; see agui_event_processor.dart's header.
    // ignore: deprecated_member_use
    ThinkingTextMessageContentEvent() ||
    // Deprecated upstream; see agui_event_processor.dart's header.
    // ignore: deprecated_member_use
    ThinkingTextMessageEndEvent() ||
    // Deprecated upstream; see agui_event_processor.dart's header.
    // ignore: deprecated_member_use
    ThinkingContentEvent() =>
      transcript,
  };
}

/// A value goes out with what it names. A tool call's records the call's kind
/// (a capability load, for one), which the call alone does not reveal; it
/// arrives right after the call's start, so one for a call no longer open is
/// dropped. A tool result's records a non-success outcome, without which
/// pydantic-ai reads the result back as a success and sends it to the
/// provider as one; it arrives right after the result. A value naming any
/// other message is dropped: it anchors reasoning, which this client does not
/// send (github.com/soliplex/frontend/issues/117).
Transcript _setEncryptedValue(
  Transcript transcript,
  ReasoningEncryptedValueEvent event,
) {
  switch (event.subtype) {
    case ReasoningEncryptedValueSubtype.message:
      final index = _indexOf(transcript, event.entityId);
      final message = index < 0 ? null : transcript.messages[index];
      if (message is! ToolMessage) {
        _logger.warning(
          'Transcript dropped an encrypted value for a message',
          attributes: {'entityId': event.entityId},
        );
        return transcript;
      }
      return transcript.withReplacedMessage(
        index,
        message.copyWith(encryptedValue: event.encryptedValue),
      );
    case ReasoningEncryptedValueSubtype.toolCall:
      final open = transcript.openToolCalls[event.entityId];
      if (open == null) {
        _logger.warning(
          'Transcript dropped an encrypted value for a tool call that is '
          'not open',
          attributes: {'toolCallId': event.entityId},
        );
        return transcript;
      }
      return transcript.copyWith(
        openToolCalls: {
          ...transcript.openToolCalls,
          event.entityId: (
            call: open.call.copyWith(encryptedValue: event.encryptedValue),
            parentId: open.parentId,
          ),
        },
      );
  }
}

Transcript _applyActivitySnapshot(
  Transcript transcript,
  ActivitySnapshotEvent event,
) {
  // `processEvent`'s display step throws on a snapshot whose content is not
  // an object, so the event reaches neither projection; the other arm is
  // never taken.
  final Map<String, dynamic> content;
  switch (event.content) {
    case final Map<String, dynamic> map:
      content = map;
    default:
      return transcript;
  }
  final index = _indexOf(transcript, event.messageId);
  if (index < 0) {
    return transcript.withAppendedMessage(
      ActivityMessage(
        id: event.messageId,
        activityType: event.activityType,
        activityContent: content,
      ),
    );
  }
  final existing = transcript.messages[index];
  if (existing is! ActivityMessage || !event.replace) {
    _logger.warning(
      'Transcript skipped an activity snapshot for an id it already holds',
      attributes: {'messageId': event.messageId},
    );
    return transcript;
  }
  return transcript.withReplacedMessage(
    index,
    existing.copyWith(
      activityType: event.activityType,
      activityContent: content,
    ),
  );
}

Transcript _applyActivityDelta(
  Transcript transcript,
  ActivityDeltaEvent event,
) {
  final index = _indexOf(transcript, event.messageId);
  final existing = index < 0 ? null : transcript.messages[index];
  if (existing != null && existing is! ActivityMessage) {
    _logger.warning(
      'Transcript skipped an activity delta for a message that is not an '
      'activity',
      attributes: {'messageId': event.messageId},
    );
    return transcript;
  }
  final patched = applyJsonPatch(
    existing is ActivityMessage ? existing.activityContent : const {},
    event.patch,
    logger: _logger,
  );
  if (!patched.complete) {
    // Whole or not at all, as the backend's parser applies a patch: sending
    // part of one would send content its producer never had.
    _logger.warning(
      'Transcript skipped an activity delta it could not apply whole',
      attributes: {'messageId': event.messageId},
    );
    return transcript;
  }
  final activity = ActivityMessage(
    id: event.messageId,
    activityType: event.activityType,
    activityContent: patched.state,
  );
  return existing == null
      ? transcript.withAppendedMessage(activity)
      : transcript.withReplacedMessage(index, activity);
}

int _indexOf(Transcript transcript, String id) =>
    transcript.messages.lastIndexWhere((m) => m.id == id);

Transcript _startText(Transcript transcript, String messageId) {
  if (_indexOf(transcript, messageId) >= 0) {
    _logger.warning(
      'Transcript skipped a text message start for an id it already holds',
      attributes: {'messageId': messageId},
    );
    return transcript;
  }
  return transcript
      .withAppendedMessage(AssistantMessage(id: messageId, content: ''));
}

Transcript _appendText(
  Transcript transcript,
  String messageId,
  String delta,
) {
  final index = _indexOf(transcript, messageId);
  final message = index < 0 ? null : transcript.messages[index];
  if (message is! AssistantMessage) {
    _logger.warning(
      'Transcript skipped text content for a message it does not hold',
      attributes: {'messageId': messageId},
    );
    return transcript;
  }
  return transcript.withReplacedMessage(
    index,
    message.copyWith(content: (message.content ?? '') + delta),
  );
}

/// The message a call naming no parent joins: the last message when it is an
/// assistant's — for the in-process providers, which emit a response's text
/// before its calls and name no parent, that is the response the call
/// belongs to — else one opened for it. The opened id comes from the
/// message's position, not the call's id: a provider that numbers its calls
/// per response gives a later response's call an earlier one's id.
String _parentOfUnnamedCall(Transcript transcript) =>
    switch (transcript.messages.lastOrNull) {
      AssistantMessage(:final id?) => id,
      _ => 'tool-calls-${transcript.messages.length}',
    };

Transcript _startToolCall(
  Transcript transcript,
  String toolCallId,
  String toolCallName,
  String? parentMessageId,
) {
  if (transcript.openToolCalls.containsKey(toolCallId)) {
    _logger.warning(
      'Transcript replaced an open tool call that never ended',
      attributes: {'toolCallId': toolCallId},
    );
  }
  final parentId = parentMessageId ?? _parentOfUnnamedCall(transcript);
  final withParent = _indexOf(transcript, parentId) >= 0
      ? transcript
      : transcript.withAppendedMessage(
          AssistantMessage(id: parentId, toolCalls: const []),
        );
  final call = ToolCall(
    id: toolCallId,
    function: FunctionCall(name: toolCallName, arguments: ''),
  );
  return withParent.copyWith(
    openToolCalls: {
      ...withParent.openToolCalls,
      toolCallId: (call: call, parentId: parentId),
    },
    unansweredToolCallIds: {...withParent.unansweredToolCallIds}
      ..remove(toolCallId),
  );
}

Transcript _appendToolCallArgs(
  Transcript transcript,
  String toolCallId,
  String delta,
) {
  final open = transcript.openToolCalls[toolCallId];
  if (open == null) {
    _logger.warning(
      'Transcript skipped arguments for a tool call that is not open',
      attributes: {'toolCallId': toolCallId},
    );
    return transcript;
  }
  final call = open.call.copyWith(
    function: open.call.function.copyWith(
      arguments: open.call.function.arguments + delta,
    ),
  );
  return transcript.copyWith(
    openToolCalls: {
      ...transcript.openToolCalls,
      toolCallId: (call: call, parentId: open.parentId),
    },
  );
}

Transcript _endToolCall(Transcript transcript, String toolCallId) {
  final open = transcript.openToolCalls[toolCallId];
  if (open == null) {
    _logger.warning(
      'Transcript skipped the end of a tool call that is not open',
      attributes: {'toolCallId': toolCallId},
    );
    return transcript;
  }
  final closed = transcript.copyWith(
    openToolCalls: {...transcript.openToolCalls}..remove(toolCallId),
  );
  final index = _indexOf(closed, open.parentId);
  final parent = index < 0 ? null : closed.messages[index];
  if (parent is! AssistantMessage) {
    // Not sent, so nothing may answer it either: a result for a call the
    // history does not hold makes pydantic-ai reject the whole history.
    _logger.warning(
      'Transcript dropped a tool call whose parent is not an assistant '
      'message',
      attributes: {'toolCallId': toolCallId, 'messageId': open.parentId},
    );
    return closed;
  }
  final call = open.call.function.arguments.isEmpty
      ? open.call.copyWith(
          function: open.call.function.copyWith(arguments: '{}'),
        )
      : open.call;
  return closed
      .withReplacedMessage(
    index,
    parent.copyWith(toolCalls: [...?parent.toolCalls, call]),
  )
      .copyWith(
    unansweredToolCallIds: {...closed.unansweredToolCallIds, toolCallId},
  );
}

/// Appends [result], a tool call's result, whether a `TOOL_CALL_RESULT`
/// carried it or a client tool produced it.
///
/// A call takes one result. A result the transcript already holds — the same
/// message, for the same call — is not appended again: a resumed run's input
/// re-sends the results its events carried. Any other result for a call with
/// none pending is skipped and logged: pydantic-ai rejects a history whose
/// result precedes its call, and a call answered twice is not one it made.
Transcript appendToolResult(Transcript transcript, ToolMessage result) {
  final toolCallId = result.toolCallId;
  if (!transcript.unansweredToolCallIds.contains(toolCallId)) {
    final held = transcript.messages.any(
      (m) =>
          m is ToolMessage && m.id == result.id && m.toolCallId == toolCallId,
    );
    if (!held) {
      _logger.warning(
        'Transcript skipped a result for a tool call with no result pending',
        attributes: {'toolCallId': toolCallId},
      );
    }
    return transcript;
  }
  return transcript.withAppendedMessage(result).copyWith(
        unansweredToolCallIds: {...transcript.unansweredToolCallIds}
          ..remove(toolCallId),
      );
}
