import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../execution_tracker.dart';

/// Collapsible log of `skill_tool_call` activities for the current
/// execution. Watches [ExecutionTracker.skillToolCalls] — one row per
/// decoded activity, keyed by `messageId`. Hides itself when empty.
class ActivityLog extends StatefulWidget {
  const ActivityLog({super.key, required this.tracker});
  final ExecutionTracker tracker;

  @override
  State<ActivityLog> createState() => _ActivityLogState();
}

class _ActivityLogState extends State<ActivityLog> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activities = widget.tracker.skillToolCalls.watch(context);
    if (activities.isEmpty) return const SizedBox.shrink();

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
                    '${activities.length} '
                    'activit${activities.length == 1 ? 'y' : 'ies'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 4),
                for (final activity in activities)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        _statusIcon(activity.status, theme),
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
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusIcon(String? status, ThemeData theme) {
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
        return Icon(
          Icons.error,
          size: 12,
          color: theme.colorScheme.error,
        );
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
}
