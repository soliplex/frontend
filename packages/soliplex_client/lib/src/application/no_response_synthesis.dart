import 'package:soliplex_client/src/application/streaming_state.dart';
import 'package:soliplex_client/src/domain/chat_message.dart';
import 'package:soliplex_client/src/domain/conversation.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex_client.no_response_synthesis');

/// Outcome of [synthesizeNoResponseIfNeeded]. The `synthesized` flag tells
/// callers whether a [NoResponseTile] was appended without forcing them to
/// compare conversations by reference.
typedef NoResponseSynthesisResult = ({
  Conversation conversation,
  bool synthesized,
});

/// Single source of truth for synthesized no-response message ids;
/// synthesis, tracker rekeying, and historical replay must derive ids
/// through this helper so they agree for the same run.
String noResponseMessageId(String runId) => '$_noResponseIdPrefix$runId';

/// Single source of truth for ids of `ErrorMessage`s synthesized when
/// `_processRunError` falls back from `NoResponseTile` synthesis (no
/// buffered thinking or unresolved tool calls).
String runErrorMessageId(String runId) => '$_runErrorIdPrefix$runId';

const _noResponseIdPrefix = 'no-response-';
const _runErrorIdPrefix = 'run-error-';

/// Appends a synthesized [NoResponseTile] to [conversation] when a run has
/// reached a terminal state with buffered thinking but no assistant
/// `TextMessageStart` / `Content` / `End` for an actual reply.
///
/// Declines (returning the input conversation and `synthesized: false`) when:
/// - [streaming] is not [AwaitingText] (a reply was in progress).
/// - The buffered thinking text is empty (no model output to preserve).
/// - The conversation has any tool call with status `pending`, `streaming`,
///   or `executing` (the run is yielding to client tools — the tool call
///   IS the response, not a missing one).
///
/// Otherwise appends a [NoResponseTile] carrying [reason] and the buffered
/// thinking so downstream UI can render the muted "Run
/// finished/failed/cancelled without a response" tile, optionally with the
/// backend error message for the `failed` case.
///
/// Throws [ArgumentError] if [terminalErrorDetail] doesn't match [reason]:
/// it must be non-null when [reason] is [TerminalReason.failed] and null
/// otherwise.
NoResponseSynthesisResult synthesizeNoResponseIfNeeded({
  required Conversation conversation,
  required StreamingState streaming,
  required String runId,
  required TerminalReason reason,
  String? terminalErrorDetail,
}) {
  if ((reason == TerminalReason.failed) != (terminalErrorDetail != null)) {
    final errorDetailState = terminalErrorDetail == null ? 'null' : 'set';
    throw ArgumentError(
      'terminalErrorDetail is required iff reason is TerminalReason.failed '
      '(reason: $reason, errorDetail: $errorDetailState)',
    );
  }
  if (streaming is! AwaitingText ||
      streaming.bufferedThinkingText.isEmpty ||
      _hasUnresolvedToolCalls(conversation)) {
    return (conversation: conversation, synthesized: false);
  }

  final tile = switch (reason) {
    TerminalReason.failed => NoResponseTile.failed(
        id: noResponseMessageId(runId),
        thinkingText: streaming.bufferedThinkingText,
        errorDetail: terminalErrorDetail!,
      ),
    TerminalReason.cancelled => NoResponseTile.cancelled(
        id: noResponseMessageId(runId),
        thinkingText: streaming.bufferedThinkingText,
      ),
    TerminalReason.finished => NoResponseTile.finished(
        id: noResponseMessageId(runId),
        thinkingText: streaming.bufferedThinkingText,
      ),
  };
  return (
    conversation: conversation.withAppendedMessage(tile),
    synthesized: true,
  );
}

/// Commits an in-flight `TextStreaming` reply as a finalized [TextMessage]
/// when a terminal event (`RunFinishedEvent`, `RunErrorEvent`, or
/// `cancelRun`) arrives mid-stream. Without this, the partial reply the
/// user was already watching vanishes when streaming is reset to
/// [AwaitingText].
///
/// No-op for [AwaitingText] or when the message id is already in the
/// conversation; the latter guards against a normal `TextMessageEnd`
/// having already finalized the same message.
///
/// [terminalEvent] is included in the log line for diagnostics — the
/// caller's name (e.g. `'RunFinishedEvent'`, `'cancelRun'`).
Conversation commitPartialTextOnTerminal({
  required Conversation conversation,
  required StreamingState streaming,
  required String runId,
  required String terminalEvent,
}) {
  if (streaming is! TextStreaming) return conversation;
  final messageId = streaming.messageId;
  if (conversation.messages.any((m) => m.id == messageId)) {
    return conversation;
  }
  _logger.info(
    'Committing partial reply text before terminal status',
    attributes: {
      'runId': runId,
      'messageId': messageId,
      'committedTextChars': streaming.text.length,
      'committedThinkingChars': streaming.thinkingText.length,
      'terminalEvent': terminalEvent,
    },
  );
  return conversation.withAppendedMessage(
    TextMessage.create(
      id: messageId,
      user: streaming.user,
      text: streaming.text,
      thinkingText: streaming.thinkingText,
    ),
  );
}

bool _hasUnresolvedToolCalls(Conversation conversation) {
  for (final tc in conversation.toolCalls) {
    if (tc.status == ToolCallStatus.pending ||
        tc.status == ToolCallStatus.streaming ||
        tc.status == ToolCallStatus.executing) {
      return true;
    }
  }
  return false;
}
