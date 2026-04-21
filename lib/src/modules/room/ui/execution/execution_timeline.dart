import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

import '../../compute_display_messages.dart' show loadingMessageId;
import '../../execution_step.dart';
import '../../execution_tracker.dart';
import '../../message_expansions.dart';
import '../../room_providers.dart';
import '../copy_button.dart';
import 'timeline_entry.dart';

/// Unified execution timeline — single collapsible that nests activities
/// under their owning step. Activity rows with source (script/code/query
/// args, or any args map) can expand to a monospace preview with a copy
/// button.
class ExecutionTimeline extends ConsumerStatefulWidget {
  const ExecutionTimeline({
    super.key,
    required this.roomId,
    required this.messageId,
    required this.tracker,
  });

  final String roomId;
  final String messageId;
  final ExecutionTracker tracker;

  @override
  ConsumerState<ExecutionTimeline> createState() => _ExecutionTimelineState();
}

class _ExecutionTimelineState extends ConsumerState<ExecutionTimeline> {
  // Sentinel-only fallbacks used while [_expansion] is null (the
  // AwaitingText phase). Once a real messageId exists, state lives in
  // the store and these are never read or written again.
  bool _loadingPhaseTimeline = false;
  final Set<String> _loadingPhaseSources = <String>{};

  // Persistence handle — null during the AwaitingText phase, because
  // loadingMessageId is reused across runs and persisting under it would
  // leak state into the next response. Captured once in initState; the
  // AwaitingText → TextStreaming transition remounts this widget under
  // a real messageId (see MessageTimeline's per-id ValueKey), at which
  // point [_expansion] becomes non-null for the rest of its life.
  MessageExpansion? _expansion;

  @override
  void initState() {
    super.initState();
    if (widget.messageId == loadingMessageId) return;
    _expansion = ref
        .read(messageExpansionsProvider)
        .forMessage(widget.roomId, widget.messageId);
  }

  bool get _expanded => _expansion?.timelineExpanded ?? _loadingPhaseTimeline;

  void _toggleExpanded() {
    setState(() {
      final next = !_expanded;
      if (_expansion != null) {
        _expansion!.timelineExpanded = next;
      } else {
        _loadingPhaseTimeline = next;
      }
    });
  }

  void _toggleSource(String activityId) {
    setState(() {
      final expansion = _expansion;
      if (expansion != null) {
        expansion.toggleSource(activityId);
        return;
      }
      if (!_loadingPhaseSources.remove(activityId)) {
        _loadingPhaseSources.add(activityId);
      }
    });
  }

  bool _isSourceExpanded(String activityId) =>
      _expansion?.isSourceExpanded(activityId) ??
      _loadingPhaseSources.contains(activityId);

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
              onTap: _toggleExpanded,
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
    final isExpanded = _isSourceExpanded(activity.messageId);

    return Padding(
      padding: EdgeInsets.only(left: indent, top: 2, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: hasSource ? () => _toggleSource(activity.messageId) : null,
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
