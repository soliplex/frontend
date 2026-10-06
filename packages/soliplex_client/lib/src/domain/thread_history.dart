import 'package:ag_ui/ag_ui.dart';
import 'package:meta/meta.dart';

import 'package:soliplex_client/src/domain/chat_message.dart';
import 'package:soliplex_client/src/domain/message_state.dart';
import 'package:soliplex_client/src/domain/thread_state_warning.dart';
import 'package:soliplex_client/src/domain/transcript.dart';

/// Result of loading thread history from the backend.
///
/// Contains both messages and AG-UI state reconstructed from stored events.
@immutable
class ThreadHistory {
  /// Creates a thread history with the given messages and AG-UI state.
  ThreadHistory({
    required List<ChatMessage> messages,
    Map<String, dynamic> aguiState = const {},
    this.aguiStateIncomplete = false,
    Map<String, MessageState> messageStates = const {},
    List<RunEventBundle> runs = const [],
    Map<String, NoResponseTile> runOutcomes = const {},
    this.documentFilter,
    List<String>? databaseSources,
    Set<ThreadStateWarning> storedStateWarnings = const {},
    this.transcript = const Transcript(),
  })  : messages = List.unmodifiable(messages),
        aguiState = Map.unmodifiable(aguiState),
        messageStates = Map.unmodifiable(messageStates),
        runs = List.unmodifiable(runs),
        runOutcomes = Map.unmodifiable(runOutcomes),
        databaseSources =
            databaseSources == null ? null : List.unmodifiable(databaseSources),
        storedStateWarnings = Set.unmodifiable(storedStateWarnings);

  /// Messages in the thread, ordered chronologically.
  final List<ChatMessage> messages;

  /// AG-UI state from STATE_SNAPSHOT and STATE_DELTA events.
  ///
  /// Contains application-specific state like citation history from RAG
  /// queries. Empty map if no state events were recorded.
  final Map<String, dynamic> aguiState;

  /// Whether [aguiState] may be missing changes a `STATE_DELTA` carried: one
  /// could not be fully applied, and no later `STATE_SNAPSHOT` replaced the
  /// state.
  final bool aguiStateIncomplete;

  /// Per-message state keyed by user message ID.
  ///
  /// Each entry contains source references (citations) associated with the
  /// assistant's response to that user message. Populated by correlating
  /// AG-UI state changes at run boundaries.
  final Map<String, MessageState> messageStates;

  /// Decoded AG-UI events grouped per run, in chronological run order.
  ///
  /// Preserves the raw event stream so consumers can reconstruct execution
  /// timelines (steps, tool calls, activities) on the reload path. Messages
  /// and citations are still derived from [messages] / [messageStates];
  /// [runs] is an additive surface for execution-tracker replay.
  final List<RunEventBundle> runs;

  /// How each run that ended ended, keyed by run id.
  ///
  /// A candidate per run, not a decision: every run that ends records one, and
  /// whoever renders the thread decides whether a run needs a tile of its own,
  /// which a run with a reply to stand for it does not.
  ///
  /// Insertion-ordered, and read that way: the order runs were recorded is the
  /// order they ended, which is what places a run that committed no message.
  final Map<String, NoResponseTile> runOutcomes;

  /// The document-filter WHERE clause the client last asserted for this thread,
  /// read from the newest run's `run_input.state.rag.document_filter`. `null`
  /// when no run carries one. The backend keeps no merged filter state, so this
  /// (not any state event) is the only record of the thread's active filter.
  final String? documentFilter;

  /// The RAG database names the client last asserted for this thread: the
  /// `sources` of the newest run whose input state carries one, under `rag`
  /// first, else any other namespace. `null` when no run carries one, or the
  /// newest carrying one asserted every database (the backend's `null`), or
  /// its value is empty or not a list of names. Like [documentFilter], the run
  /// input is the only record of it.
  final List<String>? databaseSources;

  /// What reading this thread's stored runs found it cannot use as stored.
  ///
  /// Citation warnings are collected from every run's state events, not read
  /// off [aguiState]: an answer's sources come from the state its own run
  /// ended with, so a later run replacing that state does not restore them.
  /// The scope warning is judged on the newest run input, which is what the
  /// selection UI hydrates from.
  final Set<ThreadStateWarning> storedStateWarnings;

  /// The AG-UI history the thread's next send carries.
  ///
  /// A run cut off before its terminal event adds only what it was sent; one
  /// that ended with `RUN_FINISHED` or `RUN_ERROR` adds what it streamed too.
  /// Rebuilt from the backend, a stopped run ended with `RUN_FINISHED`,
  /// because the backend finishes it and stores the rest of it; captured from
  /// the session that stopped it, it was cut off.
  final Transcript transcript;
}

/// Decoded AG-UI events for a single run, in arrival order.
@immutable
class RunEventBundle {
  /// Creates a bundle of decoded events for [runId].
  RunEventBundle({required this.runId, required List<BaseEvent> events})
      : events = List.unmodifiable(events);

  /// The run these events belong to.
  final String runId;

  /// Decoded AG-UI events in the order they were emitted.
  final List<BaseEvent> events;
}
