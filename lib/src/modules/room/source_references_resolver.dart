import 'package:soliplex_agent/soliplex_agent.dart';

/// Maps assistant message IDs to their [SourceReference] citations.
///
/// Citations are stored per user message in [MessageState]. This function
/// assigns them to the **last assistant [TextMessage]** in each turn,
/// matching the per-user-message keying of the data model.
Map<String, List<SourceReference>> buildSourceReferencesMap(
  List<ChatMessage> messages,
  Map<String, MessageState> messageStates,
) {
  final map = <String, List<SourceReference>>{};
  String? currentUserMessageId;
  String? lastAssistantTextMessageId;

  void assignPendingCitations() {
    if (currentUserMessageId == null || lastAssistantTextMessageId == null) {
      return;
    }
    final refs =
        messageStates[currentUserMessageId]?.sourceReferences ?? const [];
    if (refs.isNotEmpty) {
      map[lastAssistantTextMessageId] = refs;
    }
  }

  for (final message in messages) {
    if (message.user == ChatUser.user) {
      assignPendingCitations();
      currentUserMessageId = message.id;
      lastAssistantTextMessageId = null;
    } else if (message is TextMessage) {
      lastAssistantTextMessageId = message.id;
    }
  }

  assignPendingCitations();

  return map;
}
