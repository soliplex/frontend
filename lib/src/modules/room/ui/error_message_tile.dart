import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

class ErrorMessageTile extends StatelessWidget {
  const ErrorMessageTile({super.key, required this.message});
  final ErrorMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SelectableText(
        message.errorText,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}
