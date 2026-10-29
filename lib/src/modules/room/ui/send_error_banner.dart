import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../../../shared/selectable_content.dart';
import '../send_error.dart';
import 'copy_button.dart';

/// Reports a message that could not be sent, with its error to select or
/// copy, and a dismiss.
class SendErrorBanner extends StatelessWidget {
  const SendErrorBanner({
    super.key,
    required this.error,
    required this.onDismiss,
  });

  final SendError error;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorText = error.error.toString();
    // The copy action draws its hover, focus and press highlights on the
    // Material beneath it; Ink paints the tint there too, under them.
    return Ink(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: SoliplexSpacing.s3, vertical: SoliplexSpacing.s2),
      color: theme.colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: SelectableContent(
              child: Text(
                errorText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          // Two lines rarely hold a whole exception, and a drag can only select
          // the glyphs that were painted. This copies the untruncated text.
          CopyButton(
            text: errorText,
            tooltip: 'Copy error',
            iconSize: 16,
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: 'Dismiss',
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
