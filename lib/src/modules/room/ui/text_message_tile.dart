import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

class TextMessageTile extends StatelessWidget {
  const TextMessageTile({super.key, required this.message});
  final TextMessage message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(message.text),
    );
  }
}
