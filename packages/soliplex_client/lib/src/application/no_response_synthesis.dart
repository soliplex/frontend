import 'package:soliplex_client/src/application/streaming_state.dart';
import 'package:soliplex_client/src/domain/chat_message.dart';
import 'package:soliplex_client/src/domain/conversation.dart';

/// Id prefix for "no-response" assistant messages — assistant
/// `TextMessage`s synthesized when a run terminated with buffered thinking
/// but no actual reply (no `TextMessageStart` / `Content` / `End`).
///
/// Three production sites compose ids as `'$noResponseIdPrefix$runId'`
/// from a typed runId they already hold. They never parse the prefix
/// back — the runId is always available from the call-site context
/// (event payload, `RunState`, or `RunEventBundle`). The prefix exists
/// solely so the three sites agree on the same id for the same run:
///
/// 1. [synthesizeNoResponseIfNeeded] (this file) — constructs the id
///    when synthesizing the message during event processing.
/// 2. `ExecutionTrackerExtension._rekeyAwaitingForNoResponseIfPresent` —
///    composes the id from a terminal `RunState.runId` to look up the
///    synthesized message and rekey the awaiting tracker under it.
/// 3. `replayToTrackers` in `historical_replay.dart` — composes the id
///    from `RunEventBundle.runId` to bucket events from no-response
///    bundles under the synthesized message's tile.
///
/// Treat the value as stable; changing it requires updating all three
/// sites.
const noResponseIdPrefix = 'no-response-';

/// Appends a synthesized "no response" `TextMessage` to [conversation]
/// when a run has reached a terminal state with buffered thinking but no
/// assistant `TextMessageStart` / `Content` / `End` for an actual reply.
///
/// Returns [conversation] unchanged when:
/// - [streaming] is not [AwaitingText] (a reply was in progress).
/// - The buffered thinking text is empty (no model output to preserve).
/// - The conversation has any tool call with status `pending` or
///   `streaming` (the run is yielding to client tools — the tool call
///   IS the response, not a missing one).
///
/// Otherwise appends `TextMessage(text: '', thinkingText: <buffered>,
/// terminalReason: [reason])` so downstream UI can render the muted
/// "Run finished/failed/cancelled without a response" tile.
///
/// Used by:
/// - `processEvent` `RunFinishedEvent` arm (`reason: finished`).
/// - `processEvent` `RunErrorEvent` arm (`reason: failed`).
/// - `RunOrchestrator.cancelRun` (`reason: cancelled`).
///
/// Single helper, three call sites — keeps the synthesis condition in one
/// place.
Conversation synthesizeNoResponseIfNeeded({
  required Conversation conversation,
  required StreamingState streaming,
  required String runId,
  required TerminalReason reason,
}) {
  if (streaming is! AwaitingText) return conversation;
  if (streaming.bufferedThinkingText.isEmpty) return conversation;
  if (_hasUnresolvedToolCalls(conversation)) return conversation;

  return conversation.withAppendedMessage(
    TextMessage.create(
      id: '$noResponseIdPrefix$runId',
      user: ChatUser.assistant,
      text: '',
      thinkingText: streaming.bufferedThinkingText,
      terminalReason: reason,
    ),
  );
}

bool _hasUnresolvedToolCalls(Conversation conversation) {
  for (final tc in conversation.toolCalls) {
    if (tc.status == ToolCallStatus.pending ||
        tc.status == ToolCallStatus.streaming) {
      return true;
    }
  }
  return false;
}
