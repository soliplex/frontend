import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'copy_button.dart';
import 'package:soliplex_design/soliplex_design.dart';

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
          // design-system exception: 14/10 is the documented chat-bubble
          // padding (see design_system/README.md "the only 14").
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(soliplexRadii.md),
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
