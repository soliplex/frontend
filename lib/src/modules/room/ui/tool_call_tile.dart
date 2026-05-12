import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

class ToolCallTile extends StatelessWidget {
  const ToolCallTile({super.key, required this.message});
  final ToolCallMessage message;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .start,
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
      margin: const .symmetric(vertical: 2),
      child: ExpansionTile(
        leading: Icon(Icons.bolt, color: theme.colorScheme.primary, size: 18),
        title: Row(
          spacing: 8,
          children: [
            Flexible(
              child: Text(
                toolCall.name,
                overflow: .ellipsis,
                maxLines: 1,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: .w500),
              ),
            ),
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
            _CodeBlock(label: 'Arguments', text: toolCall.arguments),
          if (toolCall.hasResult)
            _CodeBlock(label: 'Result', text: toolCall.result),
        ],
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.label, required this.text});
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const .fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 4,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SelectableText(
            text,
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}
