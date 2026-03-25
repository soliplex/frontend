import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

class GenUiTile extends StatelessWidget {
  const GenUiTile({super.key, required this.message});
  final GenUiMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.widgetName,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              const JsonEncoder.withIndent('  ').convert(message.data),
              style:
                  theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }
}
