import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'markdown/flutter_markdown_plus_renderer.dart';

class SystemInfoTile extends StatelessWidget {
  const SystemInfoTile({super.key, required this.message});
  final SystemInfoMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      child: message.format == 'plain'
          ? SelectableText(
              message.text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : FlutterMarkdownPlusRenderer(data: message.text),
    );
  }
}
