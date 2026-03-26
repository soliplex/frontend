import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

import '../execution_step.dart';
import '../execution_tracker.dart';

ActivityType _currentActivity(StreamingState state) => switch (state) {
      AwaitingText(:final currentActivity) => currentActivity,
      TextStreaming(:final currentActivity) => currentActivity,
    };

class StreamingTile extends StatelessWidget {
  const StreamingTile({
    super.key,
    required this.streamingState,
    this.executionTracker,
  });

  final StreamingState streamingState;
  final ExecutionTracker? executionTracker;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ActivityIndicator(activity: _currentActivity(streamingState)),
          if (executionTracker != null) _StepLog(tracker: executionTracker!),
          if (executionTracker != null)
            _ThinkingBlock(tracker: executionTracker!),
          _buildStreamingContent(context),
        ],
      ),
    );
  }

  Widget _buildStreamingContent(BuildContext context) {
    final theme = Theme.of(context);
    return switch (streamingState) {
      AwaitingText() => const SizedBox.shrink(),
      TextStreaming(:final text) => Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(text.isEmpty ? '...' : text),
          ),
        ),
    };
  }
}

class _ActivityIndicator extends StatelessWidget {
  const _ActivityIndicator({required this.activity});
  final ActivityType activity;

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

class _StepLog extends StatefulWidget {
  const _StepLog({required this.tracker});
  final ExecutionTracker tracker;

  @override
  State<_StepLog> createState() => _StepLogState();
}

class _StepLogState extends State<_StepLog> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = widget.tracker.steps.watch(context);
    if (steps.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${steps.length} step${steps.length == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 4),
                for (final step in steps)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        _stepIcon(step, theme),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            step.label,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Text(
                          _formatDuration(step.elapsed),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepIcon(ExecutionStep step, ThemeData theme) {
    if (step.status == StepStatus.active) {
      return SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: theme.colorScheme.primary,
        ),
      );
    }
    final isThinking = step.label == 'Thinking';
    return Icon(
      Icons.check_circle,
      size: 12,
      color:
          isThinking ? theme.colorScheme.tertiary : theme.colorScheme.primary,
    );
  }

  static String _formatDuration(Duration d) {
    final seconds = d.inMilliseconds / 1000;
    return '${seconds.toStringAsFixed(1)}s';
  }
}

class _ThinkingBlock extends StatefulWidget {
  const _ThinkingBlock({required this.tracker});
  final ExecutionTracker tracker;

  @override
  State<_ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<_ThinkingBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thinkingText = widget.tracker.thinkingText.watch(context);
    final isStreaming = widget.tracker.isThinkingStreaming.watch(context);
    if (thinkingText.isEmpty && !isStreaming) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: theme.colorScheme.tertiary,
                width: 3,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                    color: theme.colorScheme.tertiary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Thinking',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isStreaming) ...[
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  ],
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 4),
                Text(
                  thinkingText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
