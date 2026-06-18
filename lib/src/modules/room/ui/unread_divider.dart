import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// A "New messages" separator drawn before the first unread message in a
/// thread. Colored with the primary token to match the unread dot.
class UnreadDivider extends StatelessWidget {
  const UnreadDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final labelStyle =
        Theme.of(context).textTheme.labelMedium?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.only(bottom: SoliplexSpacing.s4),
      child: Row(
        children: [
          Expanded(child: Divider(color: color)),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SoliplexSpacing.s2,
            ),
            child: Text('New messages', style: labelStyle),
          ),
          Expanded(child: Divider(color: color)),
        ],
      ),
    );
  }
}
