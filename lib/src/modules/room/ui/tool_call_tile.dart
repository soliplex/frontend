import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'execution/args_block.dart';

class ToolCallTile extends StatelessWidget {
  const ToolCallTile({super.key, required this.message});
  final ToolCallMessage message;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final toolCall in message.toolCalls)
          _ToolCallCard(toolCall: toolCall),
      ],
    );
  }
}

class _ToolCallCard extends StatelessWidget {
  const _ToolCallCard({required this.toolCall});
  final ToolCallInfo toolCall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ExpansionTile(
        leading: Icon(Icons.bolt, color: theme.colorScheme.primary, size: 18),
        title: Row(
          children: [
            Flexible(
              child: Text(
                toolCall.name,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              toolCall.status.name,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        dense: true,
        children: [
          if (toolCall.hasArguments)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ArgsBlock(raw: toolCall.arguments),
            ),
          if (toolCall.hasResult)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ArgsBlock(
                raw: toolCall.result,
                accentColor: theme.colorScheme.tertiary,
              ),
            ),
        ],
      ),
    );
  }
}
