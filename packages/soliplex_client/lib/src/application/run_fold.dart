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
@immutable
class RunFold {
  /// Opens run [runId] on [conversation].
  ///
  /// [turnCitations] carries what earlier runs of the same turn cited — a
  /// turn spans several runs when a client tool resumes it. [runCreated] is
  /// the time a row without a time of its own resolves to.
  factory RunFold.start(
    Conversation conversation, {
    required String runId,
    required String? userMessageId,
    required TurnCitations turnCitations,
    DateTime? runCreated,
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
      );

  const RunFold._({
    required this.conversation,
    required this.streaming,
    required this.runId,
    required this.userMessageId,
    required this.turnCitations,
    required this.sentTranscript,
    required this.unreadable,
    required this.eventIndex,
    required this.runCreated,
  });

  /// The conversation with every event so far folded in.
  final Conversation conversation;

  /// The reply or reasoning in flight, if any.
  final StreamingState streaming;

  /// The run being folded.
  final String runId;

  /// The message that opened the turn; keys its [MessageState].
  final String? userMessageId;

  /// What the turn has cited so far, across its runs.
  final TurnCitations turnCitations;

  /// The history the run was sent, until its state snapshot or its terminal
  /// event is processed. A run cut off before then keeps this instead of what
  /// it streamed: the snapshot, which the backend sends just before the
  /// terminal event, is the state that accounts for what it streamed, and a
  /// backend that receives a run's results without it, as haiku.rag does its
  /// evidence, can refuse the history. A run whose terminal event arrived is
  /// complete, so an ending recorded after it (a client tool failing while
  /// the run waits on it) keeps what was streamed.
  final Transcript? sentTranscript;

  /// Whether any event became a drop tile: one that could not be decoded, or
  /// one `processEvent` rejected. Either may have been the event that said
  /// how the run ended.
  final bool unreadable;

  /// Index of the next event, which names a drop tile after the stored
  /// `events[i]` it stands for. Live and replay give a drop tile the same id
  /// only because the backend stores one event per event it streams.
  final int eventIndex;

  /// When the run began, for rows without a time of their own.
  final DateTime? runCreated;

  RunFold _copyWith({
    Conversation? conversation,
    StreamingState? streaming,
    TurnCitations? turnCitations,
    bool clearSentTranscript = false,
    bool? unreadable,
    int? eventIndex,
  }) =>
      RunFold._(
        conversation: conversation ?? this.conversation,
        streaming: streaming ?? this.streaming,
        runId: runId,
        userMessageId: userMessageId,
        turnCitations: turnCitations ?? this.turnCitations,
        sentTranscript: clearSentTranscript ? null : sentTranscript,
        unreadable: unreadable ?? this.unreadable,
        eventIndex: eventIndex ?? this.eventIndex,
        runCreated: runCreated,
      );

  /// Folds [outcome] in. `processed` is the event when it reached the
  /// conversation, null when it became a drop tile instead.
  ({RunFold fold, BaseEvent? processed}) apply(DecodeOutcome outcome) {
    final index = eventIndex;
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
        final EventProcessingResult result;
        try {
          result = processEvent(
            conversation,
            streaming,
            event,
            undatedEventTime: runCreated,
          );
        } on Object catch (error, stackTrace) {
          return (
            fold: next._dropped(
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
        final userMessageId = this.userMessageId;
        if (event is RunStartedEvent && userMessageId != null) {
          folded = folded.withMessageRun(userMessageId, event.runId);
          final startedAt = runCreated;
          if (startedAt != null) {
            folded = folded.withMessageTime(userMessageId, startedAt);
          }
        }
        return (
          fold: next._copyWith(
            conversation: folded,
            streaming: result.streaming,
            turnCitations: _accumulate(result.conversation.aguiState, event),
            clearSentTranscript: switch (event) {
              StateSnapshotEvent() ||
              RunFinishedEvent() ||
              RunErrorEvent() =>
                true,
              _ => false,
            },
          ),
          processed: event,
        );
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
          createdAt: runCreated,
        ),
      ),
    );
  }

  /// Resolves the turn's citations against the current state and records
  /// them, with this run, as the turn's [MessageState]. A turn that cited
  /// nothing still gets one, so its run can be found from it.
  RunFold resolveTurn() {
    final userMessageId = this.userMessageId;
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
  String get cutOffDetail => unreadable
      ? "Some of this run's events could not be read"
      : 'Stream ended without terminal event';

  /// The run ended before its terminal event, recorded as failed with
  /// [detail]. [terminalEvent] names the ending in the log.
  RunFold failed(String detail, {required String terminalEvent}) {
    final kept = _keepingPartialReply(terminalEvent);
    return kept._copyWith(
      conversation: parkFailedOutcome(
        conversation: kept.conversation,
        streaming: streaming,
        runId: runId,
        errorDetail: detail,
        createdAt: runCreated,
      ),
      streaming: const AwaitingText(),
    );
  }

  /// The run stopped by the user before its terminal event, stamped when they
  /// stopped it. [terminalEvent] names the ending in the log.
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
  /// run was sent in place of what it streamed; see [sentTranscript].
  ///
  /// The reply the user was reading goes first, or the run's ending appears
  /// while what they were already looking at disappears.
  RunFold _keepingPartialReply(String terminalEvent) => _copyWith(
        conversation: commitPartialTextOnTerminal(
          conversation: conversation.copyWith(transcript: sentTranscript),
          streaming: streaming,
          runId: runId,
          terminalEvent: terminalEvent,
          createdAt: runCreated,
        ),
      );
}
