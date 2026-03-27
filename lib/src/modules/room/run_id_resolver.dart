import 'package:soliplex_agent/soliplex_agent.dart';

/// Maps each non-user message ID to the [MessageState.runId] of its
/// preceding user message.
///
/// Assumes messages are ordered chronologically and that each user message
/// starts a new "turn" — all subsequent non-user messages (assistant text,
/// tool calls, errors) belong to that turn until the next user message.
Map<String, String?> buildRunIdMap(
  List<ChatMessage> messages,
  Map<String, MessageState> messageStates,
) {
  final map = <String, String?>{};
  String? currentUserMessageId;

  for (final message in messages) {
    if (message.user == ChatUser.user) {
      currentUserMessageId = message.id;
    } else {
      final runId = currentUserMessageId != null
          ? messageStates[currentUserMessageId]?.runId
          : null;
      map[message.id] = runId;
    }
  }

  return map;
}
