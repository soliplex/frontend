import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

class ToolCallTile extends StatelessWidget {
  const ToolCallTile({super.key, required this.message});
  final ToolCallMessage message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(message.toolCalls.map((tc) => tc.name).join(', ')),
    );
  }
}
