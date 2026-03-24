import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

class GenUiTile extends StatelessWidget {
  const GenUiTile({super.key, required this.message});
  final GenUiMessage message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(message.widgetName),
    );
  }
}
