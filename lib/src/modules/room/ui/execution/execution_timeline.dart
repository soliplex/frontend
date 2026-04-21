import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

import '../../execution_step.dart';
import '../../execution_tracker.dart';
import '../copy_button.dart';
import 'timeline_entry.dart';

/// Unified execution timeline — single collapsible that nests activities
/// under their owning step. Activity rows with source (script/code/query
/// args, or any args map) can expand to a monospace preview with a copy
/// button.
class ExecutionTimeline extends StatefulWidget {
  const ExecutionTimeline({super.key, required this.tracker});
  final ExecutionTracker tracker;

  @override
  State<ExecutionTimeline> createState() => _ExecutionTimelineState();
}

class _ExecutionTimelineState extends State<ExecutionTimeline> {
  bool _expanded = false;
  final Set<String> _expandedSources = <String>{};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = widget.tracker.timeline.watch(context);
    if (entries.isEmpty) return const SizedBox.shrink();

    final total = entries.fold<int>(
      0,
      (sum, e) => sum + (e is TimelineStep ? 1 + e.activities.length : 1),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$total event${total == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 4),
              for (final entry in entries) _buildEntry(entry, theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEntry(TimelineEntry entry, ThemeData theme) {
    switch (entry) {
      case TimelineStep(:final step, :final activities):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _stepRow(step, theme),
            for (final activity in activities)
              _activityRow(activity, theme, indent: 20),
          ],
        );
      case TimelineOrphanActivity(:final activity):
        return _activityRow(activity, theme, indent: 0);
    }
  }

  Widget _stepRow(ExecutionStep step, ThemeData theme) {
    return Padding(
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
            _formatDuration(step.timestamp),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _activityRow(
    SkillToolCallActivity activity,
    ThemeData theme, {
    required double indent,
  }) {
    final source = _pickSource(activity);
    final hasSource = source != null;
    final isExpanded = _expandedSources.contains(activity.messageId);

    return Padding(
      padding: EdgeInsets.only(left: indent, top: 2, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: hasSource
                ? () => setState(() {
                      if (isExpanded) {
                        _expandedSources.remove(activity.messageId);
                      } else {
                        _expandedSources.add(activity.messageId);
                      }
                    })
                : null,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  child: hasSource
                      ? Icon(
                          isExpanded ? Icons.expand_more : Icons.chevron_right,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(width: 2),
                _activityStatusIcon(activity.status, theme),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    activity.toolName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (activity.status != null)
                  Text(
                    activity.status!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          if (hasSource && isExpanded) _sourceBlock(source, theme),
        ],
      ),
    );
  }

  Widget _sourceBlock(String source, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6, left: 24),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: CopyButton(text: source, iconSize: 14),
            ),
            SelectableText(
              source,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepIcon(ExecutionStep step, ThemeData theme) {
    switch (step.status) {
      case StepStatus.active:
        return SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: theme.colorScheme.primary,
          ),
        );
      case StepStatus.failed:
        return Icon(Icons.error, size: 12, color: theme.colorScheme.error);
      case StepStatus.completed:
        return Icon(
          Icons.check_circle,
          size: 12,
          color: step.type == StepType.thinking
              ? theme.colorScheme.tertiary
              : theme.colorScheme.primary,
        );
    }
  }

  Widget _activityStatusIcon(String? status, ThemeData theme) {
    switch (status) {
      case 'in_progress':
      case 'running':
        return SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: theme.colorScheme.primary,
          ),
        );
      case 'failed':
      case 'error':
        return Icon(Icons.error, size: 12, color: theme.colorScheme.error);
      case 'done':
      case 'completed':
      case 'success':
        return Icon(
          Icons.check_circle,
          size: 12,
          color: theme.colorScheme.primary,
        );
      default:
        return Icon(
          Icons.circle_outlined,
          size: 12,
          color: theme.colorScheme.outline,
        );
    }
  }

  static String? _pickSource(SkillToolCallActivity activity) {
    for (final key in const ['script', 'code', 'query']) {
      final value = activity.args[key];
      if (value is String && value.isNotEmpty) return value;
    }
    if (activity.args.isEmpty) return null;
    return const JsonEncoder.withIndent('  ').convert(activity.args);
  }

  static String _formatDuration(Duration d) {
    final seconds = d.inMilliseconds / 1000;
    return '${seconds.toStringAsFixed(1)}s';
  }
}
