import 'package:ag_ui/ag_ui.dart';
import 'package:meta/meta.dart';

import 'package:soliplex_client/src/domain/chat_message.dart';
import 'package:soliplex_client/src/domain/message_state.dart';

/// Result of loading thread history from the backend.
///
/// Contains both messages and AG-UI state reconstructed from stored events.
@immutable
class ThreadHistory {
  /// Creates a thread history with the given messages and AG-UI state.
  ThreadHistory({
    required List<ChatMessage> messages,
    Map<String, dynamic> aguiState = const {},
    Map<String, MessageState> messageStates = const {},
    List<RunEventBundle> runs = const [],
    this.documentFilter,
  })  : messages = List.unmodifiable(messages),
        aguiState = Map.unmodifiable(aguiState),
        messageStates = Map.unmodifiable(messageStates),
        runs = List.unmodifiable(runs);

  /// Messages in the thread, ordered chronologically.
  final List<ChatMessage> messages;

  /// AG-UI state from STATE_SNAPSHOT and STATE_DELTA events.
  ///
  /// Contains application-specific state like citation history from RAG
  /// queries. Empty map if no state events were recorded.
  final Map<String, dynamic> aguiState;

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

  /// The document-filter WHERE clause the client last asserted for this thread,
  /// read from the newest run's `run_input.state.rag.document_filter`. `null`
  /// when no run carries one. The backend keeps no merged filter state, so this
  /// (not any state event) is the only record of the thread's active filter.
  final String? documentFilter;
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
