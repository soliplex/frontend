import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'message_tile.dart';

class MessageTimeline extends StatelessWidget {
  const MessageTimeline({
    super.key,
    required this.messages,
    required this.messageStates,
  });

  final List<ChatMessage> messages;
  final Map<String, MessageState> messageStates;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return const Center(child: Text('No messages'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: messages.length,
      itemBuilder: (context, index) => MessageTile(
        message: messages[index],
      ),
    );
  }
}
