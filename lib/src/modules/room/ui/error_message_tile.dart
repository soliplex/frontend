import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

class ErrorMessageTile extends StatelessWidget {
  const ErrorMessageTile({super.key, required this.message});
  final ErrorMessage message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(message.errorText),
    );
  }
}
