import 'package:ag_ui/ag_ui.dart';
import 'package:collection/collection.dart';
import 'package:soliplex_client/src/api/agui_message_mapper.dart';
import 'package:soliplex_client/src/application/citation_extractor.dart';
import 'package:soliplex_client/src/application/decode_outcome.dart';
import 'package:soliplex_client/src/application/run_fold.dart';
import 'package:soliplex_client/src/application/thread_state_warnings.dart';
import 'package:soliplex_client/src/application/transcript_events.dart';
import 'package:soliplex_client/src/domain/chat_message.dart';
import 'package:soliplex_client/src/domain/conversation.dart';
import 'package:soliplex_client/src/domain/run_usage.dart';
import 'package:soliplex_client/src/domain/thread_history.dart';
import 'package:soliplex_client/src/domain/thread_state_warning.dart';
import 'package:soliplex_client/src/domain/transcript.dart';
import 'package:soliplex_client/src/errors/exceptions.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _logger = LogManager.instance.getLogger('soliplex_client.replay');

/// The user message that initiated a run, read from its persisted `run_input`
/// because the backend never echoes the user's own turn as AG-UI events.
///
/// `text` is always the message's text. `parts` is set only when the message
/// carried an attachment — an image, or a placeholder for one that could not be
/// rebuilt — the only case where the ordered form says more than `text` alone.
/// So a non-null `parts` always satisfies [TextMessage.fromParts].
typedef RunUserMessage = ({
  String messageId,
  List<MessagePart>? parts,
  String text,
});

/// What a run's GET yielded: the AG-UI events the backend streamed, plus the
/// user message that initiated the run, which those events never carry, and
/// the tool results that end its input, which they carry only for server
/// tools.
///
/// `events` is `List<Object?>` rather than `List<dynamic>` deliberately. Items
/// must survive shape drift as *data* — the replay loop mints a drop tile for
/// any non-Map entry — but `dynamic` would also switch off the static checking
/// that forces each consumer to narrow before use, which is the one thing
/// keeping that drift from becoming a runtime throw.
typedef RunPayload = ({
  List<Object?> events,
  RunUserMessage? userMessage,
  List<ToolMessage> toolResults,
});

/// One run as replay sees it: its payload joined with the identity, fetch
/// outcome, and server `created` time from the thread listing, in creation
/// order.
///
/// Separate from [RunPayload] because [RunPayload] is what the run cache
/// stores. A fetch outcome or a listing timestamp folded into it would be
/// served again on the next open of the thread, long after it stopped being
/// true.
typedef ReplayRun = ({
  String runId,
  RunPayload payload,
  SoliplexException? fetchError,
  StackTrace? fetchStackTrace,
  DateTime? created,
});

/// Rebuilds a thread's history (messages, AG-UI state and the transcript)
/// from its stored runs, in creation order: each run's user message, which
/// the backend never streams, then its events, folded by a [RunFold].
///
/// Each run's citations are keyed by the user message id that initiated it.
ThreadHistory replayThreadHistory(
  List<ReplayRun> runsToReplay,
  String threadId,
  String? documentFilter,
  List<String>? databaseSources,
  Set<ThreadStateWarning> scopeWarnings,
  RunUsage? latestUsage,
) {
  var conversation = Conversation.empty(threadId: threadId);
  final storedStateWarnings = <ThreadStateWarning>{...scopeWarnings};
  final runs = <RunEventBundle>[];
  // Text of the user messages already appended, keyed by id, so a
  // continuation run does not add its parent's message a second time. An
  // index of what this loop appended, rather than a scan of the whole
  // conversation, so it cannot be confused by an assistant message that
  // happens to share an id.
  //
  // The text is kept because a repeated id has two very different causes: a
  // continuation run re-stating the turn it continues, or one id assigned to
  // two different messages. Both drop the second message; only the first is
  // harmless, and without the text they are indistinguishable.
  final appendedUserText = <String, String>{};
  // The run replayed just before, with the user message that opened its turn.
  // A run continues that turn only when it repeats that message: it was
  // resumed from the run before it, whose citations, accumulated across every
  // run of the turn, carry on. They carry cited ids and inline figures so an
  // earlier invocation's figure survives a later invocation's `searches`
  // clear, mirroring the live path. A run that could not be fetched, or had no
  // user message, leaves none, so the run after it starts a turn of its own.
  ({String userMessageId, RunFold fold})? previousRun;
  // Where the measured run ended in the transcript, once replay reaches it.
  int? coveredByLatest;

  for (final (:runId, :payload, :fetchError, :fetchStackTrace, :created)
      in runsToReplay) {
    final events = payload.events;
    final userMessage = payload.userMessage;
    final previous = previousRun;
    previousRun = null;
    var continuesTurn = false;
    // Run-level fetch failure (transient HTTP error or pre-fetch
    // shape-drift on the run entry) → mint one drop tile in place so
    // the run is visibly missing from the timeline rather than
    // silently absent. Such a run carries no events and no user message, so
    // there is nothing to replay after it; the drop tile stands alone.
    if (fetchError != null) {
      _logger.error(
        'replay: run $runId in thread $threadId could not be fetched.',
        error: fetchError,
        stackTrace: fetchStackTrace,
      );
      conversation = conversation.withAppendedMessage(
        DroppedEventMessage.create(
          id: 'dropped-$runId-fetch',
          source: DropSource.decode,
          reason: fetchError.toString(),
          runId: runId,
          createdAt: created,
        ),
      );
    }

    // Keys this turn's citations and message state below.
    final userMessageId = userMessage?.messageId;

    // The user message is appended ahead of the events it triggered, rather
    // than folded from the stream, because the backend never sends it — the
    // same shape the live path uses, where the caller seeds the message into
    // the conversation before the stream opens.
    //
    // A run that could not be fetched has no user message to append, so its
    // drop tile stands alone.
    //
    // A repeat id is normally a continuation run, whose `run_input`'s last
    // user message is still the one its parent already contributed; the
    // turn keeps one bubble and later runs fold their events onto it.
    if (userMessage != null) {
      final appended = appendedUserText[userMessage.messageId];
      if (appended == null) {
        appendedUserText[userMessage.messageId] = userMessage.text;
        conversation = appendUserMessage(
          conversation,
          _hydratedUserMessage(userMessage, threadId, runId),
        );
      } else if (appended == userMessage.text) {
        continuesTurn = previous?.userMessageId == userMessage.messageId;
        _logger.info(
          'replay: run $runId in thread $threadId repeats message '
          '${userMessage.messageId}; not appending it twice.',
        );
      } else {
        // Same id, different message: one of the two turns is missing from
        // the timeline and the history sent, and its citations are keyed
        // onto the other.
        _logger.error(
          'replay: run $runId in thread $threadId reuses message id '
          '${userMessage.messageId} for different text; the user message of '
          'this run is dropped from the timeline and the history sent.',
        );
      }
    }

    final decodedEvents = <BaseEvent>[];
    // The events were fetched under this run's id, so the run is known
    // before any of them is read. Waiting for a `RUN_STARTED` to say so
    // leaves a bundle that carries none with every message unattributed and
    // no record of how the run ended — and the backend's own status branches
    // describe stored runs that end without the events to prove it.
    //
    // A run that could not be fetched has no events, and nothing is known of
    // how it ended; its drop tile says so, and an open run would have the
    // end-of-events rule below record how it ended.
    if (fetchError == null) {
      // The results this run's input supplied come before its events, as
      // they did when it was sent.
      conversation = conversation.copyWith(
        transcript: payload.toolResults
            .fold<Transcript>(conversation.transcript, appendToolResult),
      );
      final resumedFrom = continuesTurn ? previous?.fold : null;
      if (resumedFrom != null) {
        conversation = _resumed(conversation, resumedFrom, payload.toolResults);
      }

      var fold = RunFold.start(
        conversation,
        runId: runId,
        userMessageId: userMessageId,
        turnCitations:
            resumedFrom?.turnCitations ?? const TurnCitations.empty(),
        runCreated: created,
      );
      for (final eventJson in events) {
        final outcome = eventJson is Map<String, dynamic>
            ? decodeMapSafely(eventJson)
            : DecodeFailed(
                FormatException(
                  'Non-object item in AG-UI events: ${eventJson.runtimeType}',
                ),
                eventJson,
                StackTrace.current,
              );
        if (outcome case DecodedEvent(:final event)) decodedEvents.add(event);
        fold = fold.apply(outcome).fold;
      }
      // A stored run that ends without saying so. The backend's own unknown
      // and empty status branches describe exactly this, and the run record
      // already said the run finished — so the end of its events is the end
      // of the run, and waiting for an event to announce it would leave the
      // run with no record of how it ended and its work with no tile.
      // Recorded as a failure, as live records the same interrupted stream:
      // nothing says the run completed, and when events went unread, nothing
      // says what it answered either. The reply it was streaming is kept, and
      // the history keeps what the run was sent unless its state snapshot was
      // processed, as live does when its stream ends early.
      if (fold.conversation.status case Running()) {
        fold = fold.failed(
          fold.cutOffDetail,
          terminalEvent: 'storedRunEndedWithoutTerminal',
        );
      }
      // Resolved against this run's end-of-turn state, so the turn's last run
      // wins, mirroring the live path's resolve-at-every-terminal. Resolving
      // against the run's own state is what preserves a turn's inline figure
      // bytes: `searches` is cleared per run and a later run overwrites it,
      // while `citation_index` stays session-cumulative so the ids still
      // resolve.
      fold = fold.resolveTurn();
      conversation = fold.conversation;
      if (userMessageId != null) {
        previousRun = (userMessageId: userMessageId, fold: fold);
        // The fold dates the user message from the run's `RUN_STARTED`, as
        // live does; a stored run without one leaves it to the run record.
        if (created != null) {
          conversation = conversation.withMessageTime(userMessageId, created);
        }
      }
    }

    if (runId == latestUsage?.runId) {
      coveredByLatest = conversation.transcript.messages.length;
      // The count includes what the run was sent and what it replied, and
      // neither reaches the transcript or the next request: the reading
      // over-reads while it is shown as exact.
      if (fetchError != null) {
        _logger.warning(
          'Measured run was replayed without its events; its count covers '
          'messages the transcript does not carry',
          attributes: {'threadId': threadId, 'runId': runId},
        );
      }
    }

    // One bundle per run whose events were read, which is how a reader of the
    // history tells the runs it read from the ones it could not fetch.
    if (fetchError == null) {
      runs.add(
        RunEventBundle(
          runId: runId,
          events: decodedEvents,
          continuesTurn: continuesTurn,
        ),
      );
    }

    // Every run's end state, not only the thread's final one: each turn's
    // sources resolve against the state its own run ended with (above),
    // which a later run replaces. Fail-soft like that resolution: a warning
    // is a derived projection and must not abort the history load.
    try {
      storedStateWarnings.addAll(citationStateWarnings(conversation.aguiState));
    } on Object catch (error, stackTrace) {
      _logger.error(
        'replay: thread state warnings failed for run $runId in thread '
        '$threadId',
        stackTrace: stackTrace,
        attributes: {'failure': describeFailure(error)},
      );
    }
  }

  if (latestUsage != null && coveredByLatest == null) {
    _logger.warning(
      'Measured run was not replayed; its count is taken to cover the '
      'whole transcript',
      attributes: {'threadId': threadId, 'runId': latestUsage.runId},
    );
  }

  return ThreadHistory(
    messages: conversation.messages,
    aguiState: conversation.aguiState,
    aguiStateIncomplete: conversation.aguiStateIncomplete,
    messageStates: conversation.messageStates,
    runs: runs,
    runOutcomes: conversation.runOutcomes,
    documentFilter: documentFilter,
    databaseSources: databaseSources,
    storedStateWarnings: storedStateWarnings,
    transcript: conversation.transcript,
    // Replay never reached the measured run, so where it ended is unknown;
    // it is taken to cover the whole transcript, which estimates nothing
    // it may already count.
    latestMeasurement: latestUsage == null
        ? null
        : MeasuredRun(
            usage: latestUsage,
            coveredMessages:
                coveredByLatest ?? conversation.transcript.messages.length,
          ),
  );
}

/// [conversation] resumed from [waited], the fold of the run that waited on
/// client tools, by the run whose input supplied [results], as live resumes
/// it.
///
/// The outcome `RUN_FINISHED` parked for the waiting run is taken back,
/// because it was waiting rather than over, and the tools it waited on are
/// shown with their results: the calls are the pending ones the results
/// answer, and the results the next run was sent are the only record of what
/// they returned.
///
/// A result with an `error` is a call that failed: live sends a failed
/// call's error there as well as in its content.
Conversation _resumed(
  Conversation conversation,
  RunFold waited,
  List<ToolMessage> results,
) {
  final resumed = conversation.withoutRunOutcome(waited.runId);
  final executed = <ToolCallInfo>[];
  for (final result in results) {
    final call = resumed.toolCalls.lastWhereOrNull(
      (call) =>
          call.id == result.toolCallId && call.status == ToolCallStatus.pending,
    );
    if (call == null) continue;
    executed.add(
      call.copyWith(
        status: result.error == null
            ? ToolCallStatus.completed
            : ToolCallStatus.failed,
        result: result.content,
      ),
    );
  }
  if (executed.isEmpty) return resumed;
  return resumed.withAppendedMessage(
    ToolCallMessage.fromExecuted(
      runId: waited.runId,
      toolCalls: executed,
      createdAt: waited.undatedRowTime,
    ),
  );
}

/// The domain message for [userMessage], stamped with the run it opened.
/// Undated: the fold dates it from the run's start.
///
/// A non-null `parts` already satisfies [TextMessage.fromParts], but that
/// holds only by the postcondition [readUserMessageContent] documents rather
/// than by anything a type enforces, so it is re-checked here. An escaping
/// `ArgumentError` would cost the whole thread's history, where the one
/// message is what is actually in doubt.
///
/// Checked rather than caught: a rejection is a payload this method can
/// render around, while anything else that factory throws is a defect, and
/// catching would hide it for as long as it lives.
TextMessage _hydratedUserMessage(
  RunUserMessage userMessage,
  String threadId,
  String runId,
) {
  final parts = userMessage.parts;
  if (parts != null) {
    if (parts.plainText.isNotEmpty || parts.hasAttachment) {
      return TextMessage.fromParts(
        id: userMessage.messageId,
        parts: parts,
        runId: runId,
      );
    }
    _logger.error(
      'replay: the ordered content of message ${userMessage.messageId} in '
      'run $runId of thread $threadId carries neither an attachment nor any '
      'text; rendering it as an empty message.',
    );
  }
  return TextMessage.create(
    id: userMessage.messageId,
    user: ChatUser.user,
    text: userMessage.text,
    runId: runId,
  );
}
