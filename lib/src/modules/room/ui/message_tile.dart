import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'error_message_tile.dart';
import 'gen_ui_tile.dart';
import 'loading_message_tile.dart';
import 'text_message_tile.dart';
import 'tool_call_tile.dart';

class MessageTile extends StatelessWidget {
  const MessageTile({super.key, required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return switch (message) {
      final TextMessage m => TextMessageTile(message: m),
      final ToolCallMessage m => ToolCallTile(message: m),
      final ErrorMessage m => ErrorMessageTile(message: m),
      final GenUiMessage m => GenUiTile(message: m),
      LoadingMessage() => const LoadingMessageTile(),
    };
  }
}
