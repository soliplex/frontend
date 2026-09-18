import 'package:soliplex_client/src/application/streaming_state.dart';
import 'package:soliplex_client/src/domain/chat_message.dart';
import 'package:soliplex_client/src/domain/conversation.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex_client.no_response_synthesis');

/// Outcome of the `synthesize…NoResponse` entries. The `synthesized` flag
/// tells callers whether a [NoResponseTile] was appended without forcing
/// them to compare conversations by reference.
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

/// Id for an `ErrorMessage` synthesized when `RunErrorEvent` arrives on
/// `Idle` status (no preceding `RunStartedEvent` — backend protocol
/// violation). Hashed from [threadId] + [message] so a repeated event
/// produces a stable id, leaving id-based deduplication possible if a
/// future caller appends without first checking the conversation status.
String preRunErrorMessageId(String threadId, String message) =>
    '$_preRunErrorIdPrefix$threadId-${message.hashCode}';

const _noResponseIdPrefix = 'no-response-';
const _runErrorIdPrefix = 'run-error-';
const _preRunErrorIdPrefix = 'pre-run-error-';

/// Appends a synthesized [NoResponseTile.finished] when a run completed
/// normally with buffered thinking but no assistant text reply.
NoResponseSynthesisResult synthesizeFinishedNoResponse({
  required Conversation conversation,
  required StreamingState streaming,
  required String runId,
  DateTime? createdAt,
}) =>
    _synthesize(
      conversation: conversation,
      streaming: streaming,
      runId: runId,
      reason: TerminalReason.finished,
      buildTile: (id, thinking) => NoResponseTile.finished(
        id: id,
        thinkingText: thinking,
        createdAt: createdAt,
      ),
    );

/// Appends a synthesized [NoResponseTile.failed] when a run failed with
/// buffered thinking but no assistant text reply. [errorDetail] is the
/// backend error message; the type-level invariant on [NoResponseTile.failed]
/// requires it to be non-null.
NoResponseSynthesisResult synthesizeFailedNoResponse({
  required Conversation conversation,
  required StreamingState streaming,
  required String runId,
  required String errorDetail,
  DateTime? createdAt,
}) =>
    _synthesize(
      conversation: conversation,
      streaming: streaming,
      runId: runId,
      reason: TerminalReason.failed,
      buildTile: (id, thinking) => NoResponseTile.failed(
        id: id,
        thinkingText: thinking,
        errorDetail: errorDetail,
        createdAt: createdAt,
      ),
    );

/// Appends a synthesized [NoResponseTile.cancelled] when a run was cancelled
/// after thinking began — buffered or merely streaming — with no assistant
/// text reply.
NoResponseSynthesisResult synthesizeCancelledNoResponse({
  required Conversation conversation,
  required StreamingState streaming,
  required String runId,
  DateTime? createdAt,
}) =>
    _synthesize(
      conversation: conversation,
      streaming: streaming,
      runId: runId,
      reason: TerminalReason.cancelled,
      buildTile: (id, thinking) => NoResponseTile.cancelled(
        id: id,
        thinkingText: thinking,
        createdAt: createdAt,
      ),
    );

/// Shared decline gate for the three terminal entries.
///
/// Always declines when [streaming] is not [AwaitingText]: a reply was in
/// progress, and the caller commits that partial text instead.
///
/// Each [reason] then asks the same question — is there something the user
/// was shown that only a tile can keep? — and differs in what counts:
///
/// A cancel counts the most. The user stopped a run they were watching, so
/// anything already on screen has to survive, and only the streaming state
/// holds it. That includes the window after the reasoning-start event but
/// before its first content, which [AwaitingText.hasThinkingContent] covers
/// and an empty buffer does not, and a tool call still in flight, whose band
/// belongs to the stretch since the last thing said and so has no reply to
/// attach to.
///
/// The two backend outcomes want real thinking text, since a run that emitted
/// nothing has no missing reply to report. A finished run additionally
/// declines while a tool call is `pending`, `streaming` or `executing`,
/// because there it is yielding to client tools and the tool call IS the
/// response — the turn goes on in another run, which reaches its own
/// terminal. A failed run has no continuation to defer to, and the
/// `ErrorMessage` it falls back to carries no execution band, so it keeps
/// the tile.
///
/// Every reason also counts a run that stopped after working: its last
/// message is named as a tool call's parent, so something happened after the
/// last thing the assistant said and then the run ended. That covers a
/// response that only declared the call — an artifact of the protocol, which
/// the timeline does not show — and one that spoke first and then went quiet.
/// Either way the user is owed the account, and the band has nothing else to
/// attach to.
NoResponseSynthesisResult _synthesize({
  required Conversation conversation,
  required StreamingState streaming,
  required String runId,
  required TerminalReason reason,
  required NoResponseTile Function(String id, String thinkingText) buildTile,
}) {
  if (streaming is! AwaitingText) {
    return (conversation: conversation, synthesized: false);
  }
  final stoppedAfterWorking = _stoppedAfterWorking(conversation);
  final synthesize = switch (reason) {
    TerminalReason.cancelled => streaming.hasThinkingContent ||
        _hasUnresolvedToolCalls(conversation) ||
        stoppedAfterWorking,
    TerminalReason.finished =>
      (streaming.bufferedThinkingText.isNotEmpty || stoppedAfterWorking) &&
          !_hasUnresolvedToolCalls(conversation),
    TerminalReason.failed =>
      streaming.bufferedThinkingText.isNotEmpty || stoppedAfterWorking,
  };
  if (!synthesize) {
    return (conversation: conversation, synthesized: false);
  }
  final tile = buildTile(
    noResponseMessageId(runId),
    streaming.bufferedThinkingText,
  );
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
/// No-op for [AwaitingText], when the message id is already in the
/// conversation, or when the reply says nothing and holds no thinking. The
/// second guards against a normal `TextMessageEnd` having already finalized
/// the same message. The third is a terminal that landed between
/// `TEXT_MESSAGE_START` and the first delta, or on one carrying only
/// whitespace: there is nothing on screen to keep, and committing it would
/// state that the assistant answered with nothing where the truth is that it
/// was stopped or cut off.
///
/// [terminalEvent] is included in the log line for diagnostics — the
/// caller's name (e.g. `'RunFinishedEvent'`, `'cancelRun'`).
Conversation commitPartialTextOnTerminal({
  required Conversation conversation,
  required StreamingState streaming,
  required String runId,
  required String terminalEvent,
  DateTime? createdAt,
}) {
  if (streaming is! TextStreaming) return conversation;
  final messageId = streaming.messageId;
  if (streaming.text.trim().isEmpty && streaming.thinkingText.isEmpty) {
    _logger.info(
      'Nothing to commit on terminal: reply opened but never said anything',
      attributes: {
        'runId': runId,
        'messageId': messageId,
        'terminalEvent': terminalEvent,
      },
    );
    return conversation;
  }
  if (conversation.messages.any((m) => m.id == messageId)) {
    _logger.info(
      'Skipped duplicate message ID on partial-text commit',
      attributes: {
        'runId': runId,
        'messageId': messageId,
        'terminalEvent': terminalEvent,
      },
    );
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
      createdAt: createdAt,
    ),
  );
}

/// Whether the run did something after the last thing it said, and then
/// ended.
///
/// Asked of the *last* message, not of any: a turn that called tools and then
/// answered ends on the answer, which no call names, and has nothing missing
/// to report. A message that is named leaves work behind it — the response
/// that only declared the call, or one that spoke and then went quiet — and
/// nothing after it to carry that work or to answer the user.
///
/// Run-scoped without needing a run id: a run's conversation starts with no
/// tool calls of its own (`RunOrchestrator._buildConversation`), so only this
/// run's calls are ever in the set.
bool _stoppedAfterWorking(Conversation conversation) {
  if (conversation.messages.isEmpty) return false;
  return conversation.toolCallParentIds.contains(conversation.messages.last.id);
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
