import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../message_timestamp_format.dart';

/// Muted timestamp caption shown under a message bubble or outcome tile.
///
/// Callers render this only for messages that have a known time (a non-null
/// [time]); a message whose `createdAt` is null — the optimistic user echo or
/// an assistant reply still streaming — simply omits it. The enclosing tile's
/// `Column` handles left/right alignment.
class MessageCaption extends StatelessWidget {
  const MessageCaption({super.key, required this.time});

  final DateTime time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: SoliplexSpacing.s1),
      child: Text(
        formatMessageCaption(time),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
