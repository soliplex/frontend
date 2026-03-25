import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

class TextMessageTile extends StatelessWidget {
  const TextMessageTile({super.key, required this.message});
  final TextMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.user == ChatUser.user;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isUser ? 'You' : 'Assistant',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        if (message.hasThinkingText) ...[
          _ThinkingBlock(text: message.thinkingText),
          const SizedBox(height: 4),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isUser
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(message.text),
        ),
      ],
    );
  }
}

class _ThinkingBlock extends StatelessWidget {
  const _ThinkingBlock({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      title: Text(
        'Thinking...',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      dense: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 4),
      children: [
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            fontStyle: FontStyle.italic,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
