import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// A bubble that reports on the exchange rather than standing in for a reply.
///
/// Sits in the transcript where a reply bubble would, but on the tertiary
/// container surface and in italics, so it reads as a note about the exchange
/// rather than as something the assistant said. [label] is the caller's to
/// compose and is not necessarily app-authored: the failed-run notice folds
/// the backend's error detail into it.
class NoticeBubble extends StatelessWidget {
  const NoticeBubble({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      // design-system exception: 14/10 is the documented chat-bubble
      // padding (see design_system/README.md "the only 14").
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(context.radii.md),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onTertiaryContainer),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
