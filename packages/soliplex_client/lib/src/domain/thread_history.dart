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
  }) : messages = List.unmodifiable(messages),
       aguiState = Map.unmodifiable(aguiState),
       messageStates = Map.unmodifiable(messageStates);

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
}
