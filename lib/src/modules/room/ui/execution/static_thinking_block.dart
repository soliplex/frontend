import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../room_providers.dart';
import '../copy_button.dart';

/// A collapsible "Thinking..." block driven by a static text payload.
///
/// Persists expand/collapse state per `(roomId, messageId)` via the shared
/// `messageExpansionsProvider`. Used by message tiles that don't have an
/// active execution tracker (the tracker-driven counterpart is
/// `ExecutionThinkingBlock`).
class StaticThinkingBlock extends ConsumerWidget {
  const StaticThinkingBlock({
    super.key,
    required this.roomId,
    required this.messageId,
    required this.text,
  });

  final String roomId;
  final String messageId;
  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final expansion = ref
        .read(messageExpansionsProvider)
        .forMessage(roomId, messageId);
    // ExpansionTile reads initiallyExpanded once on mount and does not
    // rebuild when the store changes. Safe because StaticThinkingBlock and
    // ExecutionThinkingBlock are mutually exclusive for any given
    // (roomId, messageId), so only one of them writes thinkingExpanded.
    return ExpansionTile(
      initiallyExpanded: expansion.thinkingExpanded,
      onExpansionChanged: (v) => expansion.thinkingExpanded = v,
      title: Row(
        children: [
          Expanded(
            child: Text(
              'Thinking...',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          CopyButton(text: text, tooltip: 'Copy thinking', iconSize: 16),
        ],
      ),
      dense: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const .only(bottom: 4),
      children: [
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            fontStyle: .italic,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
