import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

class PhaseIndicator extends StatelessWidget {
  const PhaseIndicator({super.key, required this.phase});
  final RunPhase phase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
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

  String get _label => switch (phase) {
        ThinkingPhase() => 'Thinking...',
        ToolCallPhase(:final toolNames) when toolNames.length > 1 =>
          'Calling ${toolNames.length} tools...',
        ToolCallPhase(:final toolNames) => 'Calling ${toolNames.first}...',
        RespondingPhase() => 'Responding...',
        ProcessingPhase() => 'Processing...',
      };
}
