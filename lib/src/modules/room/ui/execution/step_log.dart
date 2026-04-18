import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../markdown/flutter_markdown_plus_renderer.dart';

import '../../execution_step.dart';
import '../../execution_tracker.dart';
import 'args_block.dart';

class StepLog extends StatefulWidget {
  const StepLog({super.key, required this.tracker});
  final ExecutionTracker tracker;

  @override
  State<StepLog> createState() => _StepLogState();
}

class _StepLogState extends State<StepLog> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = widget.tracker.steps.watch(context);
    if (steps.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: theme.colorScheme.primary.withValues(alpha: 0.4),
              width: 3,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        _expanded ? Icons.expand_more : Icons.chevron_right,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${steps.length} tool call${steps.length == 1 ? '' : 's'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_expanded) ...[
                const SizedBox(height: 2),
                for (final step in steps) _StepRow(step: step, theme: theme),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatefulWidget {
  const _StepRow({required this.step, required this.theme});
  final ExecutionStep step;
  final ThemeData theme;

  @override
  State<_StepRow> createState() => _StepRowState();
}

class _StepRowState extends State<_StepRow> {
  bool _argsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    final theme = widget.theme;
    final hasArgs = step.args != null && step.args!.isNotEmpty;

    final headerRow = Row(
      children: [
        _stepIcon(step, theme),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            step.label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w500,
              fontFamily: monospaceFont(Theme.of(context).platform),
              fontFamilyFallback: const ['monospace'],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _formatDuration(step.timestamp),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
            fontSize: 11,
          ),
        ),
        if (hasArgs) ...[
          const SizedBox(width: 4),
          Icon(
            _argsExpanded ? Icons.expand_more : Icons.chevron_right,
            size: 14,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasArgs)
            InkWell(
              onTap: () => setState(() => _argsExpanded = !_argsExpanded),
              borderRadius: BorderRadius.circular(4),
              child: headerRow,
            )
          else
            headerRow,
          if (_argsExpanded && hasArgs) ArgsBlock(raw: step.args!, indent: 20),
        ],
      ),
    );
  }

  Widget _stepIcon(ExecutionStep step, ThemeData theme) {
    switch (step.status) {
      case StepStatus.active:
        return SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: theme.colorScheme.primary,
          ),
        );
      case StepStatus.failed:
        return Icon(
          Icons.error_outline,
          size: 14,
          color: theme.colorScheme.error,
        );
      case StepStatus.completed:
        return Icon(
          Icons.check_circle_outline,
          size: 14,
          color: step.type == StepType.thinking
              ? theme.colorScheme.tertiary
              : theme.colorScheme.primary,
        );
    }
  }

  static String _formatDuration(Duration d) {
    final ms = d.inMilliseconds;
    if (ms < 1000) return '${ms}ms';
    return '${(ms / 1000).toStringAsFixed(1)}s';
  }
}
