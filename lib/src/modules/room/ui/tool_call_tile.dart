import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import '../../../../soliplex_frontend.dart';

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
      margin: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
      child: ExpansionTile(
        leading: Icon(Icons.bolt, color: theme.colorScheme.primary, size: 18),
        title: Row(
          children: [
            Flexible(
              child: Text(
                toolCall.name,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: SoliplexSpacing.s2),
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: SoliplexSpacing.s1),
          SelectableText(
            text,
            style: SoliplexTheme.mergeCode(context, theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
