import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;
import '../../../../../soliplex_frontend.dart';

class ActivityIndicator extends StatelessWidget {
  const ActivityIndicator({super.key, required this.activity});
  final ActivityType activity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: SoliplexSpacing.s2),
      child: Row(
        children: [
          const SizedBox(
            width: SoliplexSpacing.s4,
            height: SoliplexSpacing.s4,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: SoliplexSpacing.s2),
          Text(
            _label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String get _label => switch (activity) {
        ThinkingActivity() => 'Thinking...',
        ToolCallActivity(:final allToolNames) when allToolNames.length > 1 =>
          'Calling ${allToolNames.length} tools...',
        ToolCallActivity(:final allToolNames) =>
          'Calling ${allToolNames.first}...',
        RespondingActivity() => 'Responding...',
        ProcessingActivity() => 'Processing...',
      };
}
