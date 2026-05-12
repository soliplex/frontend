import 'package:soliplex_client/src/application/streaming_state.dart';
import 'package:soliplex_client/src/domain/chat_message.dart';
import 'package:soliplex_client/src/domain/conversation.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _logger = LogManager.instance.getLogger(
  'soliplex_client.no_response_synthesis',
);

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
String noResponseMessageId(String runId) => '$_kNoResponseIdPrefix$runId';

/// Single source of truth for ids of `ErrorMessage`s synthesized when
/// `_processRunError` falls back from `NoResponseTile` synthesis (no
/// buffered thinking or unresolved tool calls).
String runErrorMessageId(String runId) => '$_kRunErrorIdPrefix$runId';

/// Id for an `ErrorMessage` synthesized when `RunErrorEvent` arrives on
/// `Idle` status (no preceding `RunStartedEvent` — backend protocol
/// violation). Hashed from [threadId] + [message] so a repeated event
/// produces a stable id, leaving id-based deduplication possible if a
/// future caller appends without first checking the conversation status.
String preRunErrorMessageId(String threadId, String message) =>
    '$_kPreRunErrorIdPrefix$threadId-${message.hashCode}';

const _kNoResponseIdPrefix = 'no-response-';
const _kRunErrorIdPrefix = 'run-error-';
const _kPreRunErrorIdPrefix = 'pre-run-error-';

/// Appends a synthesized [NoResponseTile.finished] when a run completed
/// normally with buffered thinking but no assistant text reply.
NoResponseSynthesisResult synthesizeFinishedNoResponse({
  required Conversation conversation,
  required StreamingState streaming,
  required String runId,
}) => _synthesize(
  conversation: conversation,
  streaming: streaming,
  runId: runId,
  buildTile: (id, thinking) =>
      NoResponseTile.finished(id: id, thinkingText: thinking),
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
}) => _synthesize(
  conversation: conversation,
  streaming: streaming,
  runId: runId,
  buildTile: (id, thinking) => NoResponseTile.failed(
    id: id,
    thinkingText: thinking,
    errorDetail: errorDetail,
  ),
);

/// Appends a synthesized [NoResponseTile.cancelled] when a run was
/// cancelled with buffered thinking but no assistant text reply.
NoResponseSynthesisResult synthesizeCancelledNoResponse({
  required Conversation conversation,
  required StreamingState streaming,
  required String runId,
}) => _synthesize(
  conversation: conversation,
  streaming: streaming,
  runId: runId,
  buildTile: (id, thinking) =>
      NoResponseTile.cancelled(id: id, thinkingText: thinking),
);

/// Shared decline gate for the three terminal entries.
///
/// Declines (returning the input conversation and `synthesized: false`) when:
/// - [streaming] is not [AwaitingText] (a reply was in progress).
/// - The buffered thinking text is empty (no model output to preserve).
/// - The conversation has any tool call with status `pending`, `streaming`,
///   or `executing` (the run is yielding to client tools — the tool call
///   IS the response, not a missing one).
NoResponseSynthesisResult _synthesize({
  required Conversation conversation,
  required StreamingState streaming,
  required String runId,
  required NoResponseTile Function(String id, String thinkingText) buildTile,
}) {
  if (streaming is! AwaitingText ||
      streaming.bufferedThinkingText.isEmpty ||
      _hasUnresolvedToolCalls(conversation)) {
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
    ),
  );
}

bool _hasUnresolvedToolCalls(Conversation conversation) {
  for (final tc in conversation.toolCalls) {
    if (tc.status == .pending ||
        tc.status == .streaming ||
        tc.status == .executing) {
      return true;
    }
  }
  return false;
}
