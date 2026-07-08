import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../compute_display_messages.dart' show loadingMessageId;
import '../../execution_step.dart';
import '../../execution_tracker.dart';
import '../../message_expansions.dart';
import '../../room_providers.dart';
import '../copy_button.dart';
import 'timeline_entry.dart';
import 'package:soliplex_design/soliplex_design.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex_frontend.execution_timeline');

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
  // Expansion state while messageId == loadingMessageId. Kept local
  // (not in the store) because the sentinel is reused across runs —
  // persisting under it would leak open/closed state into the next
  // response.
  bool _loadingPhaseTimeline = false;
  final Set<String> _loadingPhaseSources = <String>{};

  // Throttle: log each dangling-id at most once per widget lifetime so a
  // sustained mismatch doesn't flood the logging backend on every frame.
  final Set<String> _loggedDanglingIds = <String>{};

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
    final calls = widget.tracker.skillToolCalls.watch(context);
    if (entries.isEmpty) return const SizedBox.shrink();

    final total = entries.fold<int>(
      0,
      (sum, e) => sum + (e is TimelineStep ? 1 + e.activityIds.length : 1),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: SoliplexSpacing.s2),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: SoliplexSpacing.s3, vertical: SoliplexSpacing.s2),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          // Match the message bubble's base corner (md); the events card keeps
          // uniform rounding on every corner (no speech-bubble tail).
          borderRadius: BorderRadius.circular(context.radii.md),
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
                  const SizedBox(width: SoliplexSpacing.s1),
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
              const SizedBox(height: SoliplexSpacing.s1),
              for (final entry in entries) _buildEntry(entry, theme, calls),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEntry(
    TimelineEntry entry,
    ThemeData theme,
    List<SkillToolCallActivity> calls,
  ) {
    switch (entry) {
      case TimelineStep(:final step, :final activityIds):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _stepRow(step, theme),
            for (final id in activityIds)
              if (_resolveActivity(id, calls) case final activity?)
                _activityRow(activity, theme, indent: 20),
          ],
        );
      case TimelineStandaloneActivity(:final activityId):
        final activity = _resolveActivity(activityId, calls);
        if (activity == null) return const SizedBox.shrink();
        return _activityRow(activity, theme, indent: 0);
    }
  }

  /// Looks up the decoded activity for [id] in the tracker's
  /// `skillToolCalls`. Returns `null` for a dangling id so the renderer
  /// falls through to an empty row instead of throwing. The tracker
  /// only places ids whose activityType the decoder recognises
  /// (`skill_tool_call` / `skill_tool_result`), so a dangling id
  /// indicates a real divergence — a decode failure, a
  /// `MESSAGES_SNAPSHOT` that dropped the record, or a producer/
  /// consumer mismatch. Logged at warning the first time each id fails
  /// to resolve so the dropped row is observable instead of silent.
  SkillToolCallActivity? _resolveActivity(
    String id,
    List<SkillToolCallActivity> calls,
  ) {
    for (final call in calls) {
      if (call.messageId == id) return call;
    }
    if (_loggedDanglingIds.add(id)) {
      _logger.warning(
        'ExecutionTimeline: timeline references an activity id with no '
        'matching SkillToolCallActivity; row hidden',
        attributes: {
          'activityId': id,
          'roomId': widget.roomId,
          'messageId': widget.messageId,
          'resolvableIdCount': calls.length,
        },
      );
    }
    return null;
  }

  Widget _stepRow(ExecutionStep step, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
      child: Row(
        children: [
          _stepIcon(step, theme),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: _rowLabel(
              step.label,
              theme,
              running: step.status == StepStatus.active,
            ),
          ),
          Text(
            _formatDuration(step.timestamp),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
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
      padding: EdgeInsets.only(
        left: indent,
        top: SoliplexSpacing.s1,
        bottom: SoliplexSpacing.s1,
      ),
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
                const SizedBox(width: SoliplexSpacing.s1),
                _activityStatusIcon(activity.status, theme),
                const SizedBox(width: SoliplexSpacing.s2),
                Expanded(
                  child: _rowLabel(
                    activity.toolName,
                    theme,
                    running: activity.status == SkillToolCallStatus.inProgress,
                  ),
                ),
                Text(
                  activity.status.label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
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
      padding: const EdgeInsets.only(
        top: SoliplexSpacing.s1,
        bottom: SoliplexSpacing.s2,
        left: SoliplexSpacing.s6,
      ),
      child: Container(
        padding: const EdgeInsets.all(SoliplexSpacing.s2),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(context.radii.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: CopyButton(text: source, iconSize: 14),
            ),
            Text(
              source,
              style: context
                  .monospaceOn(theme.textTheme.labelSmall)
                  .copyWith(height: 1.3),
            ),
          ],
        ),
      ),
    );
  }

  /// The primary label of a timeline row. While the row is [running] the text
  /// shimmers (a calm stand-in for the old per-row spinner) and settles back to
  /// the plain muted label — same resting color — once the step completes.
  Widget _rowLabel(String label, ThemeData theme, {required bool running}) {
    final text = Text(
      label,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    if (!running) return text;
    return SoliplexShimmerText(child: text);
  }

  Widget _stepIcon(ExecutionStep step, ThemeData theme) {
    switch (step.status) {
      case StepStatus.active:
        // No spinner: the shimmering label carries the "in progress" signal.
        // Keep the slot so completed rows' check icons stay column-aligned.
        return const SizedBox(width: 12, height: 12);
      case StepStatus.failed:
        return Icon(Icons.error, size: 12, color: theme.colorScheme.error);
      case StepStatus.completed:
        return Icon(
          Icons.check_circle,
          size: 12,
          // A completed action is a success result → SymbolicColors.success.
          // Thinking keeps a tertiary accent to read as reflection, not a
          // pass/fail outcome.
          color: step.type == StepType.thinking
              ? theme.colorScheme.tertiary
              : context.success,
        );
    }
  }

  Widget _activityStatusIcon(SkillToolCallStatus status, ThemeData theme) {
    switch (status) {
      case SkillToolCallStatus.inProgress:
        // No spinner: the shimmering label carries the "in progress" signal.
        return const SizedBox(width: 12, height: 12);
      case SkillToolCallStatus.error:
        return Icon(Icons.error, size: 12, color: theme.colorScheme.error);
      case SkillToolCallStatus.done:
        return Icon(
          Icons.check_circle,
          size: 12,
          color: context.success,
        );
      case SkillToolCallStatus.unknown:
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
