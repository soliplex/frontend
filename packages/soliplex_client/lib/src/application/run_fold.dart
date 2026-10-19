import 'package:ag_ui/ag_ui.dart';
import 'package:meta/meta.dart';
import 'package:soliplex_client/src/application/agui_event_processor.dart';
import 'package:soliplex_client/src/application/citation_extractor.dart';
import 'package:soliplex_client/src/application/decode_outcome.dart';
import 'package:soliplex_client/src/application/run_ending.dart';
import 'package:soliplex_client/src/application/streaming_state.dart';
import 'package:soliplex_client/src/domain/chat_message.dart';
import 'package:soliplex_client/src/domain/conversation.dart';
import 'package:soliplex_client/src/domain/message_state.dart';
import 'package:soliplex_client/src/domain/source_reference.dart';
import 'package:soliplex_client/src/domain/transcript.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex_client.run_fold');

final _citationExtractor = CitationExtractor();

/// One AG-UI run folded into a [Conversation], event by event.
///
/// The live stream (`RunOrchestrator`) and a reopened thread's stored events
/// (`replayThreadHistory`) both reach the conversation through this, so a run
/// reads the same either way.
@immutable
class RunFold {
  /// Opens run [runId] on [conversation].
  ///
  /// [turnCitations] carries what earlier runs of the same turn cited — a
  /// turn spans several runs when a client tool resumes it. [runCreated] is
  /// the time a row without a time of its own resolves to until an event
  /// carries one.
  factory RunFold.start(
    Conversation conversation, {
    required String runId,
    required String? userMessageId,
    required TurnCitations turnCitations,
    required DateTime? runCreated,
  }) =>
      RunFold._(
        conversation: conversation.withStatus(Running(runId: runId)),
        streaming: const AwaitingText(),
        runId: runId,
        userMessageId: userMessageId,
        turnCitations: turnCitations,
        sentTranscript: conversation.transcript,
        unreadable: false,
        eventIndex: 0,
        runCreated: runCreated,
        lastEventTime: null,
      );

  const RunFold._({
    required this.conversation,
    required this.streaming,
    required this.runId,
    required String? userMessageId,
    required this.turnCitations,
    required Transcript? sentTranscript,
    required bool unreadable,
    required int eventIndex,
    required DateTime? runCreated,
    required DateTime? lastEventTime,
  })  : _userMessageId = userMessageId,
        _sentTranscript = sentTranscript,
        _unreadable = unreadable,
        _eventIndex = eventIndex,
        _runCreated = runCreated,
        _lastEventTime = lastEventTime;

  /// The conversation with every event so far folded in.
  final Conversation conversation;

  /// The reply or reasoning in flight, if any.
  final StreamingState streaming;

  /// The run being folded.
  final String runId;

  /// The message that opened the turn; keys its [MessageState].
  final String? _userMessageId;

  /// What the turn has cited so far, across its runs.
  final TurnCitations turnCitations;

  /// The history the run was sent, until its state snapshot or its
  /// `RUN_FINISHED` is processed. A run cut off before then keeps this instead
  /// of what it streamed: the snapshot, which the backend sends just before
  /// the terminal event, is the state that accounts for what it streamed, and
  /// a backend that receives a run's results without it, as haiku.rag does its
  /// evidence, can refuse the history. A run that finished is complete, so an
  /// ending recorded after it (a client tool failing while the run waits on
  /// it) keeps what was streamed.
  final Transcript? _sentTranscript;

  /// Whether any event became a drop tile: one that could not be decoded, or
  /// one `processEvent` rejected. Either may have been the event that said
  /// how the run ended.
  final bool _unreadable;

  /// Index of the next event, which names a drop tile after the stored
  /// `events[i]` it stands for. Live and replay give a drop tile the same id
  /// only because the backend stores one event per event it streams.
  final int _eventIndex;

  /// When the run began, for rows before any event carried a time.
  final DateTime? _runCreated;

  /// The server time of the latest event that carried a usable one.
  final DateTime? _lastEventTime;

  /// The time a row without one of its own resolves to: the latest event so
  /// far that carried a time, or the run's start before any did. The run's
  /// start alone would sort a row minted at the end of the run above the reply
  /// it follows.
  DateTime? get undatedRowTime => _lastEventTime ?? _runCreated;

  RunFold _copyWith({
    Conversation? conversation,
    StreamingState? streaming,
    TurnCitations? turnCitations,
    bool clearSentTranscript = false,
    bool? unreadable,
    int? eventIndex,
    DateTime? lastEventTime,
  }) =>
      RunFold._(
        conversation: conversation ?? this.conversation,
        streaming: streaming ?? this.streaming,
        runId: runId,
        userMessageId: _userMessageId,
        turnCitations: turnCitations ?? this.turnCitations,
        sentTranscript: clearSentTranscript ? null : _sentTranscript,
        unreadable: unreadable ?? _unreadable,
        eventIndex: eventIndex ?? _eventIndex,
        runCreated: _runCreated,
        lastEventTime: lastEventTime ?? _lastEventTime,
      );

  /// This fold paused on a client tool: the outcome its `RUN_FINISHED` parked
  /// is taken back, because the run is waiting rather than over, and
  /// [streaming] — the state it paused in, which `RUN_FINISHED` reset — is
  /// what an ending recorded during the wait carries.
  RunFold pausedForClientTools({required StreamingState streaming}) =>
      _copyWith(
        conversation: conversation.withoutRunOutcome(runId),
        streaming: streaming,
      );

  /// Folds [outcome] in. `processed` is the event when it reached the
  /// conversation, null when it became a drop tile instead.
  ({RunFold fold, BaseEvent? processed}) apply(DecodeOutcome outcome) {
    final index = _eventIndex;
    final next = _copyWith(eventIndex: index + 1);
    switch (outcome) {
      case DecodeFailed(:final error, :final rawData, :final stackTrace):
        return (
          fold: next._dropped(
            index,
            DropSource.decode,
            error,
            stackTrace,
            rawData,
          ),
          processed: null,
        );
      case DecodedEvent(:final event, :final rawJson):
        final timed = next._copyWith(lastEventTime: _eventTime(event));
        final EventProcessingResult result;
        try {
          result = processEvent(
            conversation,
            streaming,
            event,
            createdAt: timed.undatedRowTime,
          );
        } on Object catch (error, stackTrace) {
          return (
            fold: timed._dropped(
              index,
              DropSource.eventProcessing,
              error,
              stackTrace,
              rawJson,
              eventType: event.runtimeType,
            ),
            processed: null,
          );
        }
        var folded = result.conversation;
        // The turn's user message takes the run that started the turn and its
        // start time. Both only fill what is empty, so a client tool's
        // continuation run leaves the message with the run that sent it.
        final userMessageId = _userMessageId;
        if (event is RunStartedEvent && userMessageId != null) {
          folded = folded.withMessageRun(userMessageId, event.runId);
          final startedAt = timed.undatedRowTime;
          if (startedAt != null) {
            folded = folded.withMessageTime(userMessageId, startedAt);
          }
        }
        return (
          fold: timed._copyWith(
            conversation: folded,
            streaming: result.streaming,
            turnCitations: _accumulate(result.conversation.aguiState, event),
            clearSentTranscript: switch (event) {
              StateSnapshotEvent() || RunFinishedEvent() => true,
              _ => false,
            },
          ),
          processed: event,
        );
    }
  }

  /// The server time [event] carries, or null when it carries none or one no
  /// date can hold.
  DateTime? _eventTime(BaseEvent event) {
    final timestamp = event.timestamp;
    if (timestamp == null) return null;
    try {
      return DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true);
    } on Object catch (error) {
      // What this can throw carries only the timestamp, a number the backend
      // stamps and no secret, and it is what makes the record actionable.
      _logger.warning(
        'Ignoring invalid event timestamp ($timestamp) on run $runId',
        error: error,
      );
      return null;
    }
  }

  /// [turnCitations] with what [event] cited, read from [state], the state
  /// after it. Fail-soft: citations are a derived projection, and the event
  /// has already been processed.
  TurnCitations _accumulate(Map<String, dynamic> state, BaseEvent event) {
    try {
      return switch (event) {
        StateDeltaEvent() =>
          _citationExtractor.accumulate(turnCitations, state, event),
        StateSnapshotEvent() =>
          _citationExtractor.accumulateSnapshot(turnCitations, state),
        _ => turnCitations,
      };
    } on Object catch (error, stackTrace) {
      _logger.error(
        'Citation accumulation failed on run $runId (${event.runtimeType})',
        error: error,
        stackTrace: stackTrace,
      );
      return turnCitations;
    }
  }

  RunFold _dropped(
    int index,
    DropSource source,
    Object error,
    StackTrace? stackTrace,
    Object? rawPayload, {
    Type? eventType,
  }) {
    _logger.error(
      eventType == null
          ? 'Dropped event $index of run $runId (${source.name})'
          : 'processEvent threw on $eventType, event $index of run $runId',
      attributes: {'failure': describeFailure(error)},
      stackTrace: stackTrace,
    );
    return _copyWith(
      unreadable: true,
      conversation: conversation.withAppendedMessage(
        DroppedEventMessage.create(
          id: 'dropped-$runId-$index',
          source: source,
          reason: error.toString(),
          runId: runId,
          rawPayload: rawPayload,
          createdAt: undatedRowTime,
        ),
      ),
    );
  }

  /// Resolves the turn's citations against the current state and records
  /// them, with this run, as the turn's [MessageState]. A turn that cited
  /// nothing still gets one, so its run can be found from it.
  RunFold resolveTurn() {
    final userMessageId = _userMessageId;
    if (userMessageId == null) return this;
    final state = conversation.aguiState;
    var sources = const <SourceReference>[];
    try {
      sources = _citationExtractor.resolve(
        turnCitations,
        state,
        logContext: 'run $runId',
      );
    } on Object catch (error, stackTrace) {
      _logger.error(
        'Citation resolution failed for run $runId',
        error: error,
        stackTrace: stackTrace,
      );
    }
    _logger.info(
      'Citations: run $runId resolved ${sources.length} source(s) from '
      '${turnCitations.ids.length} cited id(s), '
      '${sources.where((s) => s.figures.isNotEmpty).length} with figures.',
    );
    _warnOnUncreditedIds(state);
    return _copyWith(
      conversation: conversation.withMessageState(
        userMessageId,
        MessageState(
          userMessageId: userMessageId,
          sourceReferences: sources,
          runId: runId,
        ),
      ),
    );
  }

  /// Warns when [state] names cited ids [turnCitations] never took in.
  ///
  /// An id the state says was cited but that no carrier fed into the
  /// accumulator means this build cannot read the record's carrier; the
  /// counts above all derive from the accumulator, so without this the
  /// shortfall reads as a turn that simply cited nothing.
  void _warnOnUncreditedIds(Map<String, dynamic> state) {
    final Set<String> uncredited;
    try {
      uncredited = _citationExtractor
          .citationsInState(state)
          .ids
          .difference(turnCitations.ids);
    } on Object catch (error, stackTrace) {
      _logger.error(
        'Citations: uncredited-id check failed for run $runId',
        error: error,
        stackTrace: stackTrace,
      );
      return;
    }
    if (uncredited.isEmpty) return;
    _logger.warning(
      'Citations: run $runId ended with ${uncredited.length} cited id(s) '
      'present in state but never accumulated; the rendered source list is '
      'short. ids: $uncredited',
    );
  }

  /// Why a run that ended without its terminal event failed, as its outcome
  /// tile says it.
  String get cutOffDetail => _unreadable
      ? "Some of this run's events could not be read"
      : 'Stream ended without terminal event';

  /// The run recorded as failed with [detail]: cut off before its terminal
  /// event, or ended while it waited on a client tool. [terminalEvent] names
  /// the ending in the log.
  RunFold failed(String detail, {required String terminalEvent}) {
    final kept = _keepingPartialReply(terminalEvent);
    return kept._copyWith(
      conversation: parkFailedOutcome(
        conversation: kept.conversation,
        streaming: streaming,
        runId: runId,
        errorDetail: detail,
        createdAt: undatedRowTime,
      ),
      streaming: const AwaitingText(),
    );
  }

  /// The run recorded as stopped — by the user, by a dispose, or while it
  /// waited on a client tool — stamped with the client clock when the stop is
  /// recorded. [terminalEvent] names the ending in the log.
  RunFold cancelled({required String terminalEvent}) {
    final kept = _keepingPartialReply(terminalEvent);
    return kept._copyWith(
      conversation: parkCancelledOutcome(
        conversation: kept.conversation,
        streaming: streaming,
        runId: runId,
        createdAt: DateTime.timestamp(),
      ),
      streaming: const AwaitingText(),
    );
  }

  /// This fold with the reply it was streaming committed, and with what the
  /// run was sent in place of what it streamed; see [_sentTranscript].
  ///
  /// The reply the user was reading goes first, or the run's ending appears
  /// while what they were already looking at disappears.
  RunFold _keepingPartialReply(String terminalEvent) => _copyWith(
        conversation: commitPartialTextOnTerminal(
          conversation: conversation.copyWith(transcript: _sentTranscript),
          streaming: streaming,
          runId: runId,
          terminalEvent: terminalEvent,
          createdAt: undatedRowTime,
        ),
      );
}
