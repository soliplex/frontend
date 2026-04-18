import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../markdown/flutter_markdown_plus_renderer.dart';

import '../../execution_activity.dart';
import '../../execution_tracker.dart';
import 'args_block.dart';

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
    final all = widget.tracker.activities.watch(context);
    // Only show activities that have something useful to display
    final activities = all.where(_isUseful).toList();
    if (activities.isEmpty) return const SizedBox.shrink();

    final count = activities.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: theme.colorScheme.secondary.withValues(alpha: 0.5),
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
                      Icon(
                        Icons.account_tree_outlined,
                        size: 13,
                        color: theme.colorScheme.secondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$count sub-agent call${count == 1 ? '' : 's'}',
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
                for (final entry in activities)
                  _ActivityRow(entry: entry, theme: theme),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static bool _isUseful(ActivityEntry entry) {
    switch (entry.activityType) {
      case 'skill_tool_call':
        final args = entry.content['args'];
        return args is String && args.isNotEmpty;
      case 'skill_tool_result':
        final result = _extractResult(entry.content);
        return result != null && result.trim().isNotEmpty;
      default:
        return false; // unknown types hidden unless we explicitly handle them
    }
  }

  static String? _extractResult(Map<String, dynamic> content) {
    final r = content['result'];
    if (r == null) return null;
    if (r is String) return r.isEmpty ? null : r;
    return const JsonEncoder.withIndent('  ').convert(r);
  }
}

class _ActivityRow extends StatefulWidget {
  const _ActivityRow({required this.entry, required this.theme});
  final ActivityEntry entry;
  final ThemeData theme;

  @override
  State<_ActivityRow> createState() => _ActivityRowState();
}

class _ActivityRowState extends State<_ActivityRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final theme = widget.theme;
    final isResult = entry.activityType == 'skill_tool_result';
    final (primaryLabel, secondaryLabel) = _labelParts(entry);
    final payload = _payload(entry);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: payload != null
                ? () => setState(() => _expanded = !_expanded)
                : null,
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: [
                Icon(
                  isResult
                      ? Icons.call_received_outlined
                      : Icons.call_made_outlined,
                  size: 13,
                  color: isResult
                      ? theme.colorScheme.tertiary
                      : theme.colorScheme.secondary,
                ),
                const SizedBox(width: 6),
                if (payload != null) ...[
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 2),
                ],
                Expanded(
                  child: RichText(
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: primaryLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w500,
                            fontFamily:
                                monospaceFont(Theme.of(context).platform),
                            fontFamilyFallback: const ['monospace'],
                          ),
                        ),
                        if (secondaryLabel != null)
                          TextSpan(
                            text: '  $secondaryLabel',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Text(
                  _formatDuration(entry.timestamp),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (_expanded && payload != null)
            ArgsBlock(
              raw: payload,
              indent: 18,
              accentColor: isResult ? theme.colorScheme.tertiary : null,
            ),
        ],
      ),
    );
  }

  static (String, String?) _labelParts(ActivityEntry entry) {
    final c = entry.content;
    final skill = c['skill'] as String?;
    final tool = c['tool_name'] as String?;
    if (skill != null && tool != null) {
      return (tool, skill);
    }
    return (entry.activityType, null);
  }

  static String? _payload(ActivityEntry entry) {
    final c = entry.content;
    switch (entry.activityType) {
      case 'skill_tool_call':
        final args = c['args'];
        if (args is String && args.isNotEmpty) return args;
        return null;
      case 'skill_tool_result':
        final r = c['result'];
        if (r == null) return null;
        if (r is String) return r.isEmpty ? null : r;
        return const JsonEncoder.withIndent('  ').convert(r);
    }
    return null;
  }

  static String _formatDuration(Duration d) {
    final ms = d.inMilliseconds;
    if (ms < 1000) return '${ms}ms';
    return '${(ms / 1000).toStringAsFixed(1)}s';
  }
}
