import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'copy_button.dart';
import '../../../../soliplex_frontend.dart';

class ErrorMessageTile extends StatelessWidget {
  const ErrorMessageTile({super.key, required this.message});
  final ErrorMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: SoliplexSpacing.s3, vertical: SoliplexSpacing.s3),
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
        ),
        const SizedBox(height: SoliplexSpacing.s1),
        CopyButton(text: message.errorText),
      ],
    );
  }
}
