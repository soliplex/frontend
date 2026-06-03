import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;
import '../../../../design/design.dart';

class PhaseIndicator extends StatelessWidget {
  const PhaseIndicator({super.key, required this.phase});
  final RunPhase phase;

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

  String get _label => switch (phase) {
        ThinkingPhase() => 'Thinking...',
        ToolCallPhase(:final toolNames) when toolNames.length > 1 =>
          'Calling ${toolNames.length} tools...',
        ToolCallPhase(:final toolNames) => 'Calling ${toolNames.first}...',
        RespondingPhase() => 'Responding...',
        ProcessingPhase() => 'Processing...',
      };
}
