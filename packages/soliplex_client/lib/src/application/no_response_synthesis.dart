import 'package:soliplex_client/src/application/streaming_state.dart';
import 'package:soliplex_client/src/domain/chat_message.dart';
import 'package:soliplex_client/src/domain/conversation.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex_client.no_response_synthesis');

/// Single source of truth for the id of a run's parked outcome. It doubles as
/// the key of a band that collected while no message had spoken, so parking,
/// band keying on both paths, and placement all have to derive it here for the
/// three to agree about the same run.
String noResponseMessageId(String runId) => '$_noResponseIdPrefix$runId';

/// Id of the row that reports a failed run which has something else to show
/// for itself, and so shows no outcome tile of its own to carry the failure.
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

/// Records how a run that finished normally ended, for a thread that may have
/// nothing else to show for it.
Conversation parkFinishedOutcome({
  required Conversation conversation,
  required StreamingState streaming,
  required String runId,
  DateTime? createdAt,
}) =>
    _park(
      conversation: conversation,
      streaming: streaming,
      runId: runId,
      build: (id, thinking) => NoResponseTile.finished(
        id: id,
        thinkingText: thinking,
        createdAt: createdAt,
        runId: runId,
      ),
    );

/// Records how a run that failed ended. [errorDetail] is what the tile shows
/// as the reason — the backend's message when the failure came from there, and
/// the caller's own description when it did not.
Conversation parkFailedOutcome({
  required Conversation conversation,
  required StreamingState streaming,
  required String runId,
  required String errorDetail,
  DateTime? createdAt,
}) =>
    _park(
      conversation: conversation,
      streaming: streaming,
      runId: runId,
      build: (id, thinking) => NoResponseTile.failed(
        id: id,
        thinkingText: thinking,
        errorDetail: errorDetail,
        createdAt: createdAt,
        runId: runId,
      ),
    );

/// Records that the user stopped a run.
Conversation parkCancelledOutcome({
  required Conversation conversation,
  required StreamingState streaming,
  required String runId,
  DateTime? createdAt,
}) =>
    _park(
      conversation: conversation,
      streaming: streaming,
      runId: runId,
      build: (id, thinking) => NoResponseTile.cancelled(
        id: id,
        thinkingText: thinking,
        createdAt: createdAt,
        runId: runId,
      ),
    );

/// Parks [runId]'s outcome, always.
///
/// Nothing here asks whether the run has anything else to show for itself.
/// That question needs the whole thread — a run that answered has a reply to
/// stand for it — and the answer is not available at the moment a run ends.
/// Parking a candidate and letting the thread decide replaces three guesses
/// that each had to be right: that a reply was not mid-stream, that some
/// reasoning had been buffered, and that no tool call was still open.
///
/// The reasoning travels with the candidate, from whichever state the run was
/// in when it stopped. A reply already committed carries its own copy, and a
/// candidate whose run has a reply to stand for it is simply not shown.
Conversation _park({
  required Conversation conversation,
  required StreamingState streaming,
  required String runId,
  required NoResponseTile Function(String id, String thinkingText) build,
}) {
  final thinking = switch (streaming) {
    AwaitingText(:final bufferedThinkingText) => bufferedThinkingText,
    TextStreaming(:final thinkingText) => thinkingText,
  };
  return conversation.withRunOutcome(
    runId,
    build(noResponseMessageId(runId), thinking),
  );
}

/// Commits an in-flight `TextStreaming` reply as a finalized [TextMessage]
/// when a terminal event (`RunFinishedEvent`, `RunErrorEvent`, or
/// `cancelRun`) arrives mid-stream. Without this, the partial reply the
/// user was already watching vanishes when streaming is reset to
/// [AwaitingText].
///
/// No-op for [AwaitingText], when the message id is already in the
/// conversation, or when the reply holds neither text nor thinking. The
/// second guards against a normal `TextMessageEnd` having already finalized
/// the same message. The third is a terminal that landed between
/// `TEXT_MESSAGE_START` and the first delta: there is nothing on screen to
/// keep, and committing an empty reply would state that the assistant
/// answered with nothing where the truth is that it was stopped or cut off.
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
  if (streaming.text.isEmpty && streaming.thinkingText.isEmpty) {
    _logger.info(
      'Nothing to commit on terminal: reply opened but never received text',
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
      runId: runId,
    ),
  );
}
