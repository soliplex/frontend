import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// The standing caveat under the composer — the slot a chat product reserves
/// for what the user should know before sending — saying that the thing
/// answering is a model and can be wrong.
///
/// Renders on every deployment: it reads no setting and has no empty state, so
/// no configuration can suppress it.
class ChatAiDisclaimer extends StatelessWidget {
  const ChatAiDisclaimer({super.key, required this.appName});

  /// The product's own name, so the caveat says what the user thinks they are
  /// talking to rather than a vendor name they have never seen.
  final String appName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: SoliplexSpacing.s4,
        right: SoliplexSpacing.s4,
      ),
      child: Text(
        // Full stop: the line wraps at narrow widths, and it marks the last
        // line as the sentence ending rather than a truncation.
        '$appName is AI and can make mistakes.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
