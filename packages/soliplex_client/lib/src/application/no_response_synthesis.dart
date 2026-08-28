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
      preserveWhateverWasShown: false,
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
      preserveWhateverWasShown: false,
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
      // Whatever the user was already looking at has to outlive the Stop —
      // a Thinking indicator with no content yet, or thinking beside a tool
      // call still in flight. Declining either blanks the exchange.
      preserveWhateverWasShown: true,
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
/// [preserveWhateverWasShown] then chooses between two policies.
///
/// A cancel sets it. The user stopped a run they were watching, so anything
/// already on screen has to survive, and only the streaming state holds it —
/// the tile is what carries it afterwards. That includes the window after the
/// reasoning-start event but before its first content, which
/// [AwaitingText.hasThinkingContent] covers and an empty buffer does not, and
/// it includes a tool call still in flight.
///
/// The two backend outcomes clear it. They require real thinking text, since a
/// run that emitted nothing has no missing reply to report, and they decline
/// while any tool call is `pending`, `streaming` or `executing`, because there
/// the run is yielding to client tools and the tool call IS the response. That
/// yield never reaches the cancel path: `cancelRun` handles
/// `ToolYieldingState` in its own branch, so an unresolved tool call seen here
/// after a cancel is a backend call mid-flight, which shows the user nothing.
NoResponseSynthesisResult _synthesize({
  required Conversation conversation,
  required StreamingState streaming,
  required String runId,
  required bool preserveWhateverWasShown,
  required NoResponseTile Function(String id, String thinkingText) buildTile,
}) {
  if (streaming is! AwaitingText) {
    return (conversation: conversation, synthesized: false);
  }
  final synthesize = preserveWhateverWasShown
      ? streaming.hasThinkingContent
      : streaming.bufferedThinkingText.isNotEmpty &&
          !_hasUnresolvedToolCalls(conversation);
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
  DateTime? createdAt,
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
      createdAt: createdAt,
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
