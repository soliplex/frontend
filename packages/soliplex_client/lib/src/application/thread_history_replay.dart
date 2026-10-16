import 'package:ag_ui/ag_ui.dart';
import 'package:collection/collection.dart';
import 'package:soliplex_client/src/api/agui_message_mapper.dart';
import 'package:soliplex_client/src/api/mappers.dart';
import 'package:soliplex_client/src/application/citation_extractor.dart';
import 'package:soliplex_client/src/application/decode_outcome.dart';
import 'package:soliplex_client/src/application/rag_snapshot.dart'
    show ragSourcesKey, ragStateKey;
import 'package:soliplex_client/src/application/replay_observer.dart';
import 'package:soliplex_client/src/application/run_fold.dart';
import 'package:soliplex_client/src/application/thread_state_warnings.dart';
import 'package:soliplex_client/src/application/transcript_events.dart';
import 'package:soliplex_client/src/domain/chat_message.dart';
import 'package:soliplex_client/src/domain/conversation.dart';
import 'package:soliplex_client/src/domain/rag_document.dart';
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

/// What fetching one run's payload yielded. A run whose fetch failed
/// carries [noRunData] and the error that kept it from being read.
typedef FetchedRun = ({
  String runId,
  RunPayload payload,
  SoliplexException? fetchError,
  StackTrace? fetchStackTrace,
});

/// A run with nothing to replay. `events` is empty rather than null so the
/// replay loop reads one shape either way.
///
/// Not a sentinel: records compare field-wise, so a run the backend genuinely
/// returned empty can compare equal to this. What marks a run as missing is its
/// `fetchError`, never a comparison against this value.
const RunPayload noRunData = (
  events: <Object?>[],
  userMessage: null,
  toolResults: <ToolMessage>[],
);

/// Builds the history of thread [threadId] from its listing, [thread],
/// fetching each finished run's payload through [fetchRun]. No unfinished run
/// is fetched; the newest may be reported as [ThreadHistory.runInProgress],
/// read from the listing alone.
///
/// Throws [MalformedResponseException] when the listing's `runs` has an
/// unexpected shape. Whatever [fetchRun] throws fails the whole history; a
/// run becomes a drop tile only when [fetchRun] returns its failure as the
/// [FetchedRun]'s `fetchError`.
Future<ThreadHistory> assembleThreadHistory(
  Map<String, dynamic> thread,
  String threadId,
  Future<FetchedRun> Function(String runId) fetchRun, {
  required ReplayObserver? observer,
}) async {
  // Envelope-level shape drift (`runs` arrives as a list/scalar instead
  // of a map) is a backend bug — retry can't fix it. Throw so the UI
  // surfaces a non-retryable error rather than rendering an empty
  // thread (which is indistinguishable from a fresh thread). Null /
  // missing stays a legitimate empty thread.
  final rawRuns = thread['runs'];
  if (rawRuns != null && rawRuns is! Map<String, dynamic>) {
    throw MalformedResponseException(
      message: 'Thread history `runs` field has unexpected shape: '
          '${rawRuns.runtimeType}',
    );
  }
  final runs =
      rawRuns is Map<String, dynamic> ? rawRuns : const <String, dynamic>{};
  if (runs.isEmpty) return ThreadHistory(messages: const []);
  final documentFilter = _extractLatestDocumentFilter(runs);
  final databaseSources = _extractLatestDatabaseSources(runs);
  final scopeWarnings = {
    if (_latestScopeUnreadable(runs)) ThreadStateWarning.scopeUnreadable,
  };
  final latestUsage = _extractLatestUsage(runs);

  // 1. Walk runs once, in creation order. Each becomes a slot: a completed
  //    run to fetch, or a malformed entry, kept as a drop-tile placeholder
  //    so the run is visibly absent rather than silently filtered out (its
  //    `runId` is then the entry's key). Unfinished runs are not replayed:
  //    their stored events are only what they have sent so far. The newest
  //    one, if it was sent a message, is the candidate run in progress.
  final slots = <({
    String runId,
    MalformedResponseException? malformed,
    DateTime? created,
  })>[];
  final sorted = _sortRunsByCreationTime(runs);
  final runInProgress = _runInProgress(sorted.last, threadId);
  for (final MapEntry(:key, :value) in sorted) {
    final created = _runCreated(value, key, threadId);
    if (value is! Map<String, dynamic>) {
      slots.add(
        (
          runId: key,
          malformed: MalformedResponseException(
            message: 'Run entry $key has unexpected shape: '
                '${value.runtimeType}',
          ),
          created: created,
        ),
      );
      continue;
    }
    if (value['finished'] == null) {
      if (key != sorted.last.key && value['run_input'] != null) {
        _logger.warning(
          'replay: an unfinished run is older than a later run in the '
          'thread; it is not shown or followed.',
          attributes: {'threadId': threadId, 'runId': key},
        );
      }
      continue;
    }
    final rawRunId = value['run_id'];
    // Blank is rejected alongside the wrong type: a run id stands in for a
    // missing message id below, where two runs sharing one would have the
    // second's message dropped as a repeat.
    if (rawRunId is! String || rawRunId.isEmpty) {
      final got =
          rawRunId is String ? 'an empty String' : '${rawRunId.runtimeType}';
      slots.add(
        (
          runId: key,
          malformed: MalformedResponseException(
            message: 'Run entry $key missing `run_id` (got $got)',
          ),
          created: created,
        ),
      );
      continue;
    }
    slots.add((runId: rawRunId, malformed: null, created: created));
  }

  if (slots.isEmpty) {
    return ThreadHistory(
      messages: const [],
      documentFilter: documentFilter,
      databaseSources: databaseSources,
      storedStateWarnings: scopeWarnings,
      // Nothing was replayed, so the transcript is empty and the count
      // covers none of it.
      latestMeasurement: latestUsage == null
          ? null
          : MeasuredRun(usage: latestUsage, coveredMessages: 0),
      runInProgress: runInProgress,
    );
  }

  // 2. Fetch all run events in parallel
  final results = await Future.wait([
    for (final slot in slots)
      if (slot.malformed == null) fetchRun(slot.runId),
  ]);

  // 3. The slots in creation order, each with what its fetch returned
  //    (results may arrive out of order).
  final fetchByRunId = {for (final r in results) r.runId: r};
  final runsToReplay = <ReplayRun>[
    for (final (:runId, :malformed, :created) in slots)
      if (malformed != null)
        (
          runId: runId,
          payload: noRunData,
          fetchError: malformed,
          // Built here, not thrown, so there is no stack worth carrying.
          fetchStackTrace: null,
          created: created,
        )
      else
        (
          runId: runId,
          payload: fetchByRunId[runId]!.payload,
          fetchError: fetchByRunId[runId]!.fetchError,
          fetchStackTrace: fetchByRunId[runId]!.fetchStackTrace,
          created: created,
        ),
  ];

  // 4. Replay events to reconstruct history (messages, AG-UI state and the
  //    transcript)
  return replayThreadHistory(
    runsToReplay,
    threadId,
    documentFilter,
    databaseSources,
    scopeWarnings,
    latestUsage,
    runInProgress,
    observer: observer,
  );
}

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
  RunInProgress? runInProgress, {
  required ReplayObserver? observer,
}) {
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
      observer?.runStarted(fold, continuesTurn: continuesTurn);
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
        final applied = fold.apply(outcome);
        fold = applied.fold;
        observer?.eventFolded(fold, processed: applied.processed);
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
        RunEventBundle(runId: runId, continuesTurn: continuesTurn),
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

  // A run in progress whose message the thread already holds continues that
  // message's turn, as a run resumed after a client tool does. Following it
  // would need the turn resumed as live resumes it (the waiting run's outcome
  // taken back, the tool results it was sent added), so it is not reported.
  var followable = runInProgress;
  if (followable != null &&
      appendedUserText.containsKey(followable.userMessage.id)) {
    _logger.info(
      'replay: the run in progress continues a turn the thread already '
      'holds; it is not followed.',
      attributes: {'threadId': threadId, 'runId': followable.runId},
    );
    followable = null;
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
    runInProgress: followable,
  );
}

/// [newest], the thread's newest run entry, as the run in progress: one the
/// backend has not finished and that was sent a user message.
///
/// A run is created before it is sent anything, so an unfinished run with no
/// stored input is one nobody has written in yet, such as a new thread's
/// initial run, and not a run still going.
RunInProgress? _runInProgress(
  MapEntry<String, dynamic> newest,
  String threadId,
) {
  final value = newest.value;
  if (value is! Map<String, dynamic> || value['finished'] != null) {
    return null;
  }
  final runId = value['run_id'];
  if (runId is! String || runId.isEmpty) {
    // A run that was never sent anything is not a run in progress either way;
    // one that was is lost from the thread here, and this is the only place
    // that can say so.
    if (value['run_input'] != null) {
      _logger.warning(
        'replay: the newest run has no usable `run_id`; it is not followed.',
        attributes: {'threadId': threadId, 'runId': newest.key},
      );
    }
    return null;
  }
  final userMessage = _extractUserMessage(value, threadId, runId);
  if (userMessage == null) return null;
  return RunInProgress(
    runId: runId,
    userMessage: _hydratedUserMessage(userMessage, threadId, runId),
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

/// [rawRun], the GET of run [runId] in thread [threadId], read as the
/// payload replay folds.
///
/// `events` is `List<Object?>` rather than `List<Map<String, dynamic>>`:
/// shape drift on the wire (a non-Map item slipping into `events`)
/// must reach [replayThreadHistory] as data, not throw at the cast
/// site. The replay loop type-checks each item and mints a drop tile
/// for non-Map entries.
///
/// `events` not being a list at all is the one drift that cannot become a
/// drop tile — there is no item to mint one for — so it is logged instead.
RunPayload runPayloadFromJson(
  Map<String, dynamic> rawRun,
  String threadId,
  String runId,
) {
  final rawEvents = rawRun['events'];
  if (rawEvents is! List && rawEvents != null) {
    // Absent is normal for a run that streamed nothing; present-but-wrong-
    // shape erases every reply the run produced, and this is the only place
    // it is visible.
    _logger.warning(
      'replay: run $runId in thread $threadId has `events` as '
      '${rawEvents.runtimeType}, not a list; the run replays as empty.',
    );
  }
  return (
    events: rawEvents is List ? rawEvents : const <Object?>[],
    userMessage: _extractUserMessage(rawRun, threadId, runId),
    toolResults: _extractToolResults(rawRun, threadId, runId),
  );
}

/// The user message that initiated the run [runId], read from `run_input`.
///
/// Each run's `run_input.messages` contains the full conversation context,
/// but only the last user message initiated THIS run. Prior user messages
/// were already processed in earlier runs.
///
/// Null when the run carries no user message to rebuild. That costs more than
/// the message itself — [replayThreadHistory] keys the turn's citations
/// and message state off its id — so every shape that reaches it by drift
/// rather than by absence is logged.
RunUserMessage? _extractUserMessage(
  Map<String, dynamic> rawRun,
  String threadId,
  String runId,
) {
  // Type-checked rather than cast: shape drift here degrades to "no user
  // message" rather than aborting the run-level fetch.
  final runInput = rawRun['run_input'];
  if (runInput is! Map<String, dynamic>) {
    // Absent is normal for a run the backend has not persisted input for;
    // present-but-wrong-shape is drift only findable here.
    if (runInput != null) {
      _logger.warning(
        'replay: run $runId in thread $threadId has `run_input` as '
        '${runInput.runtimeType}, not an object; its user message and tool '
        'results are lost, and with the message the citations for that turn.',
      );
    }
    return null;
  }

  final rawMessages = runInput['messages'];
  if (rawMessages is! List) {
    if (rawMessages != null) {
      _logger.warning(
        'replay: run $runId in thread $threadId has `run_input.messages` as '
        '${rawMessages.runtimeType}, not a list; its user message and tool '
        'results are lost, and with the message the citations for that turn.',
      );
    }
    return null;
  }

  // Find the last user message — the one that initiated this run.
  Map<String, dynamic>? lastUserMessage;
  for (var i = rawMessages.length - 1; i >= 0; i--) {
    final raw = rawMessages[i];
    if (raw is! Map<String, dynamic>) continue;
    final role = raw['role'];
    if ((role is String ? role : 'user') == 'user') {
      lastUserMessage = raw;
      break;
    }
  }
  if (lastUserMessage == null) {
    if (rawMessages.isNotEmpty) {
      _logger.warning(
        'replay: run $runId in thread $threadId carries '
        '${rawMessages.length} input message(s) but none from the user; '
        'the turn has no citations or message state.',
      );
    }
    return null;
  }

  // A blank id is no more usable than a missing one: the append guard in
  // `replayThreadHistory` appends one message per id, so every blank-id
  // turn in a thread would collapse onto the first. Both fall back
  // to the run's own id, which the thread listing rejects unless it is a
  // non-empty String — so two runs cannot collide on it.
  final rawId = lastUserMessage['id'];
  if (rawId is! String || rawId.isEmpty) {
    _logger.warning(
      'replay: the user message initiating run $runId in thread $threadId '
      'has no usable id; keying it to the run instead.',
    );
  }
  final id = rawId is String && rawId.isNotEmpty ? rawId : 'user-$runId';
  final content = readUserMessageContent(
    lastUserMessage['content'],
    logContext: 'message $id in run $runId of thread $threadId',
  );

  return (messageId: id, parts: content.parts, text: content.text);
}

/// The tool messages that end run [runId]'s input, after its last other
/// message, in order. For a client tool each is the only record of its
/// result; for a server tool it may repeat one the run's events carried.
/// Each is read whole, as the backend's own client keeps a stored message,
/// so an `error` or `encryptedValue` another client recorded goes back too.
///
/// Only the tail is read: every input repeats the thread's earlier results,
/// and a server that numbers its calls per response reuses ids, so an
/// earlier result would answer a later call that reuses its id. An input
/// that ends with the user's message supplies none.
///
/// A malformed `run_input` or `messages` is already reported by
/// [_extractUserMessage], so it reads here as no results.
List<ToolMessage> _extractToolResults(
  Map<String, dynamic> rawRun,
  String threadId,
  String runId,
) {
  final runInput = rawRun['run_input'];
  if (runInput is! Map<String, dynamic>) return const [];
  final rawMessages = runInput['messages'];
  if (rawMessages is! List) return const [];

  final results = <ToolMessage>[];
  for (final raw in rawMessages.reversed) {
    if (raw is! Map<String, dynamic>) {
      _logger.warning(
        'replay: an item in the input of run $runId in thread $threadId is '
        'not an object; the tool results before it are not read.',
      );
      break;
    }
    if (raw['role'] != 'tool') break;
    try {
      results.add(ToolMessage.fromJson(raw));
    } on AGUIValidationError {
      _logger.warning(
        'replay: a tool message in the input of run $runId in thread '
        '$threadId could not be read as a tool message; the call it '
        'answers keeps no result from it.',
      );
    }
  }
  return results.reversed.toList();
}

/// The `document_filter` from the newest run that carries one in its
/// persisted input state. The backend returns runs in ascending creation
/// order (`Thread.runs` is `order_by="Run.created"`), and that order is
/// preserved through the JSON dict into [runs], so the last entry carrying
/// the key is the newest — no dependence on any per-run `created` value.
/// Each run stores the complete filter it was sent (the client re-asserts it
/// every run; the backend keeps no merged state), so the newest run's value
/// IS the current filter — there is nothing to accumulate. An explicit null
/// on the newest carrying run means "cleared" and wins over older runs.
/// A run whose input or state is not a map is skipped; a newest value that
/// is neither null nor a string reads as null, which
/// [_latestScopeUnreadable] flags.
String? _extractLatestDocumentFilter(Map<String, dynamic> runs) {
  final filter = _latestStateValue(runs, 'document_filter');
  return filter is String ? filter : null;
}

/// The `sources` from the newest run whose input state carries one, or
/// null.
///
/// Each namespace a selection is written to is sent the part of it that
/// namespace lists. A room's skills cover one database set, so each carries
/// the same list and the first found speaks for the run — `rag` first, for a
/// room with several. A room with only the analysis skill has it under
/// `analysis` alone.
///
/// A list with a non-string entry reads as null: the selector cannot have
/// sent it, and "every database" is the reading that loses nothing.
List<String>? _extractLatestDatabaseSources(Map<String, dynamic> runs) {
  final sources = _latestStateValue(runs, ragSourcesKey, anyNamespace: true);
  if (sources is! List || sources.isEmpty) return null;
  final names = <String>[];
  for (final entry in sources) {
    if (entry is! String) return null;
    names.add(entry);
  }
  return names;
}

/// Whether the newest run's saved `document_filter` or `sources` is one the
/// selection UI cannot hydrate, so it starts from no document or every
/// database. A filter is unreadable when it is neither null nor a string,
/// or a non-empty string [parseDocumentFilter] finds no id in; an empty one
/// is no filter to haiku.rag, as it is to the UI. `sources` is unreadable
/// when it is neither null nor a list of names.
bool _latestScopeUnreadable(Map<String, dynamic> runs) {
  final filter = _latestStateValue(runs, 'document_filter');
  final sources = _latestStateValue(runs, ragSourcesKey, anyNamespace: true);
  final filterUnreadable = filter != null &&
      (filter is! String ||
          (filter.isNotEmpty && parseDocumentFilter(filter).isEmpty));
  final sourcesUnreadable =
      sources != null && (sources is! List || sources.any((s) => s is! String));
  return filterUnreadable || sourcesUnreadable;
}

/// The value under [key] in the newest run's `run_input.state.rag` that
/// carries the key at all — a run carrying it as `null` is an answer, not a
/// run to skip past. With [anyNamespace], a run is also read through any
/// other namespace carrying the key when `rag` does not.
Object? _latestStateValue(
  Map<String, dynamic> runs,
  String key, {
  bool anyNamespace = false,
}) {
  for (final entry in runs.entries.toList().reversed) {
    final value = entry.value;
    if (value is! Map<String, dynamic>) continue;
    final runInput = value['run_input'];
    if (runInput is! Map<String, dynamic>) continue;
    final state = runInput['state'];
    if (state is! Map<String, dynamic>) continue;
    final namespaces = [
      state[ragStateKey],
      if (anyNamespace)
        for (final other in state.entries)
          if (other.key != ragStateKey) other.value,
    ];
    for (final namespace in namespaces) {
      if (namespace is! Map<String, dynamic>) continue;
      if (!namespace.containsKey(key)) continue;
      return namespace[key];
    }
  }
  return null;
}

/// The newest run's usage that measured the context, or null.
///
/// Walks runs newest-first and stops at the first with a
/// `final_input_tokens`, so a run the model never answered — which records
/// no usage, or one without a count — is skipped in favour of the one
/// before it.
///
/// A run with no `created` is passed over rather than read. The sort
/// puts it at the end, so this walk would otherwise meet it first —
/// and without a time there is nothing to call it the newest by. An
/// unfinished run is read: its usage is written once, when the stream
/// completes, so a row that exists is a whole measurement.
///
/// A record that is not an object, whose count is not an integer, or whose
/// run has no `run_id` ends the walk instead of continuing it. The
/// thread's messages must not fail to load over an indicator, but an
/// unreadable record may hold the newest count, and nothing tells it apart
/// from a run that measured nothing. So the walk stops rather than present
/// an older count as the one that stands.
RunUsage? _extractLatestUsage(Map<String, dynamic> runs) {
  for (final entry in _sortRunsByCreationTime(runs).reversed) {
    final value = entry.value;
    if (value is! Map<String, dynamic>) continue;
    if (value['created'] is! String) continue;
    final usage = value['usage'];
    // A run the model never answered recorded no usage, or one without a
    // count; the run before it still stands.
    if (usage == null ||
        (usage is Map<String, dynamic> &&
            usage['final_input_tokens'] == null)) {
      continue;
    }
    final runId = value['run_id'];
    if (usage is Map<String, dynamic> &&
        usage['final_input_tokens'] is int &&
        runId is String &&
        runId.isNotEmpty) {
      return runUsageFromJson(runId, usage);
    }
    // The thread reports no measurement from here, which on its own
    // reads as a thread nobody has counted. This says the record was
    // there and could not be read, and names which one.
    _logger.warning(
      'Usage record could not be read; the thread reports none',
      attributes: {'runId': entry.key},
    );
    return null;
  }
  return null;
}

/// Resolves a run map's `created` to a UTC [DateTime] via [parseTimestamp]
/// (which reads a naive ISO-8601 string as UTC), or null when the field is
/// absent. A present-but-wrong-shaped or malformed value logs a warning and
/// resolves to null, leaving the run's replayed messages without a displayed
/// timestamp rather than substituting a client `now()`.
DateTime? _runCreated(dynamic runData, String runId, String threadId) {
  if (runData is! Map<String, dynamic>) return null;
  final created = runData['created'];
  if (created == null) return null;
  if (created is! String) {
    _logger.warning(
      'replay: run $runId in thread $threadId has a non-string `created` '
      '(${created.runtimeType}); resolving to no timestamp.',
    );
    return null;
  }
  try {
    return parseTimestamp(created);
  } on FormatException catch (error) {
    // Expected shape drift: a malformed `created` string. Routine — warn
    // and resolve to no timestamp.
    _logger.warning(
      'replay: run $runId in thread $threadId has a malformed `created` '
      'timestamp; resolving to no timestamp.',
      error: error,
    );
    return null;
  } on Object catch (error, stackTrace) {
    // parseTimestamp is documented to throw only FormatException; anything
    // else is an unexpected contract break worth a louder signal. Still
    // resolve to null so one run never aborts the whole history replay.
    _logger.error(
      'replay: run $runId in thread $threadId threw unexpectedly parsing '
      '`created`; resolving to no timestamp.',
      error: error,
      stackTrace: stackTrace,
    );
    return null;
  }
}

/// Sorts runs by creation time (oldest first). Non-Map run values
/// sort to the end; the caller filters them out before fetching.
List<MapEntry<String, dynamic>> _sortRunsByCreationTime(
  Map<String, dynamic> runs,
) {
  return runs.entries.toList()
    ..sort((a, b) {
      final aData = a.value is Map<String, dynamic>
          ? a.value as Map<String, dynamic>
          : const <String, dynamic>{};
      final bData = b.value is Map<String, dynamic>
          ? b.value as Map<String, dynamic>
          : const <String, dynamic>{};
      final aCreated =
          aData['created'] is String ? aData['created'] as String : null;
      final bCreated =
          bData['created'] is String ? bData['created'] as String : null;

      if (aCreated == null && bCreated == null) return 0;
      if (aCreated == null) return 1;
      if (bCreated == null) return -1;

      // Use tryParse to handle malformed timestamps gracefully
      final epoch = DateTime.fromMillisecondsSinceEpoch(0);
      final aTime = DateTime.tryParse(aCreated) ?? epoch;
      final bTime = DateTime.tryParse(bCreated) ?? epoch;
      return aTime.compareTo(bTime);
    });
}
