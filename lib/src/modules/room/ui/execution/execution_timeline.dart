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

/// Argument names whose value is the point of the call, in the order they are
/// preferred — a sandbox script, executed code, a search query, a shell
/// command. When an args object carries one, showing it beats showing the whole
/// object.
const List<String> _sourceKeys = ['script', 'code', 'query', 'command'];

/// Left inset of a row nested under a step, clearing the step's own disclosure
/// chevron and status icon so the nesting stays legible. Written as the sum it
/// clears so it cannot drift from the row it is measured against.
const double _nestedIndent = _disclosureWidth +
    SoliplexSpacing.s1 +
    _statusIconSize +
    SoliplexSpacing.s2;

/// Width reserved for a row's disclosure chevron, kept even when the row has
/// nothing to disclose so status icons stay column-aligned.
const double _disclosureWidth = 14;

/// Size of a row's status icon, and of the disclosure chevron drawn beside it.
const double _statusIconSize = 12;

/// Lines of a source body shown before the reader asks for the rest. A
/// retrieval result runs to tens of thousands of characters, which would bury
/// every row after it. Clamped by line count rather than pixels so the clamp
/// holds the same shape at every text scale.
const int _collapsedSourceLines = 8;

/// Suffixes distinguishing the two things a tool call row can disclose, so each
/// keys its own entry in the expansion store.
const String _argsClampSuffix = '#args';
const String _resultClampSuffix = '#result';

/// Execution timeline — a single collapsible listing a run's steps, nesting
/// any activity rows under their owning step. A step row carrying a server tool
/// call, and an activity row carrying a source, expand to a monospace preview
/// with a copy button.
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

  void _toggleSource(String sourceKey) {
    setState(() {
      final expansion = _expansion;
      if (expansion != null) {
        expansion.toggleSource(sourceKey);
        return;
      }
      if (!_loadingPhaseSources.remove(sourceKey)) {
        _loadingPhaseSources.add(sourceKey);
      }
    });
  }

  bool _isSourceExpanded(String sourceKey) =>
      _expansion?.isSourceExpanded(sourceKey) ??
      _loadingPhaseSources.contains(sourceKey);

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
      case TimelineStep(:final activityIds):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _stepRow(entry, theme),
            for (final id in activityIds)
              if (_resolveActivity(id, calls) case final activity?)
                _activityRow(activity, theme, indent: _nestedIndent),
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

  Widget _stepRow(TimelineStep entry, ThemeData theme) {
    final step = entry.step;
    final id = entry.toolCallId;
    final args = entry.args.isEmpty ? null : _formatArgs(entry.args);
    final result = (entry.result?.isEmpty ?? true) ? null : entry.result;
    // A server tool call's args and result are the call's own detail, so the
    // step expands in place. A step with no id carries no detail of its own and
    // keeps the slot only so icons stay column-aligned.
    final hasDetail = id != null && (args != null || result != null);
    final isExpanded = hasDetail && _isSourceExpanded(id);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: hasDetail ? () => _toggleSource(id) : null,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                SizedBox(
                  width: _disclosureWidth,
                  child: hasDetail
                      ? Icon(
                          isExpanded ? Icons.expand_more : Icons.chevron_right,
                          size: _disclosureWidth,
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(width: SoliplexSpacing.s1),
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
          ),
          if (isExpanded) ...[
            if (args != null)
              _sourceBlock(
                args,
                theme,
                label: 'Arguments',
                clampId: '$id$_argsClampSuffix',
              ),
            // AG-UI carries no field for a failed outcome, so a tool that hit a
            // limit or raised delivers its message through the ordinary result
            // string. Rendering it is the only way that text reaches the user.
            if (result != null)
              _sourceBlock(
                result,
                theme,
                label: 'Result',
                clampId: '$id$_resultClampSuffix',
              ),
          ],
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

  /// A source block whose body clamps to [_collapsedSourceLines] until the
  /// reader asks for the rest.
  ///
  /// [clampId] keys that per block, so expanding one call's result leaves every
  /// other row alone. Pass null to render the body in full, which the activity
  /// path does because this change leaves its rendering as it was.
  Widget _sourceBlock(
    String source,
    ThemeData theme, {
    String? label,
    String? clampId,
  }) {
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
            Row(
              children: [
                if (label != null)
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const Spacer(),
                // Copies the whole body regardless of what is on screen.
                CopyButton(text: source, iconSize: 14),
              ],
            ),
            _sourceBody(source, theme, clampId),
          ],
        ),
      ),
    );
  }

  Widget _sourceBody(String source, ThemeData theme, String? clampId) {
    final style =
        context.monospaceOn(theme.textTheme.labelSmall).copyWith(height: 1.3);
    if (clampId == null) return Text(source, style: style);

    final expanded = _isSourceExpanded(clampId);
    // Read outside the builder so layout does not take a MediaQuery dependency.
    final textScaler = MediaQuery.textScalerOf(context);
    // Measure before deciding: a body that fits shows no control, for the same
    // reason a step with no detail shows no chevron.
    return LayoutBuilder(
      builder: (context, constraints) {
        final overflows = _overflowsClamp(
          source,
          style,
          textScaler,
          Directionality.of(context),
          constraints.maxWidth,
        );
        final clamped = overflows && !expanded;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              source,
              style: style,
              maxLines: clamped ? _collapsedSourceLines : null,
              overflow: clamped ? TextOverflow.ellipsis : TextOverflow.clip,
            ),
            if (overflows)
              GestureDetector(
                onTap: () => _toggleSource(clampId),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(top: SoliplexSpacing.s1),
                  child: Row(
                    children: [
                      // The row disclosures elsewhere encode state (right when
                      // closed, down when open) because they carry no words.
                      // This one is labelled with a verb, so the arrow points
                      // at what the tap does: down to reveal, up to collapse.
                      Icon(
                        expanded ? Icons.expand_less : Icons.expand_more,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: SoliplexSpacing.s1),
                      Text(
                        expanded ? 'Show less' : 'Show more',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// The primary label of a timeline row. While the row is [running] the text
  /// shimmers (a calmer signal than a per-row spinner) and settles back to
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
        return const SizedBox(
          width: _statusIconSize,
          height: _statusIconSize,
        );
      case StepStatus.failed:
        return Icon(
          Icons.error,
          size: _statusIconSize,
          color: theme.colorScheme.error,
        );
      case StepStatus.completed:
        return Icon(
          Icons.check_circle,
          size: _statusIconSize,
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

  /// Whether [source] needs more than [_collapsedSourceLines] to render at
  /// [maxWidth], and so warrants a disclosure control.
  ///
  /// Counts explicit line breaks first: a body already carrying that many
  /// provably overflows, and the bodies that do — tens of KB of retrieved chunk
  /// text — are the ones whose measurement is expensive. Laying one out is a
  /// full line-break pass on the UI thread, repeated for every expanded block
  /// each time an args delta rebuilds the timeline.
  ///
  /// [textScaler] must be the one the rendered [Text] will use; measuring
  /// unscaled would report a body as fitting that the reader sees overflow.
  static bool _overflowsClamp(
    String source,
    TextStyle style,
    TextScaler textScaler,
    TextDirection textDirection,
    double maxWidth,
  ) {
    var breaks = 0;
    for (var i = 0; i < source.length; i++) {
      if (source.codeUnitAt(i) != 0x0A) continue;
      if (++breaks >= _collapsedSourceLines) return true;
    }
    final painter = TextPainter(
      text: TextSpan(text: source, style: style),
      maxLines: _collapsedSourceLines,
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth);
    final overflows = painter.didExceedMaxLines;
    painter.dispose();
    return overflows;
  }

  /// Renders a tool call's accumulated `TOOL_CALL_ARGS` for display, or null
  /// when there is nothing worth showing.
  ///
  /// Prefers the one field that carries the intent — the script, the code, the
  /// query, the command — over the whole object. Falls back to the raw string
  /// when it does not parse: while the call is still streaming the accumulation
  /// is a JSON prefix, and a partial payload is more useful shown than hidden.
  /// A tool that takes no arguments sends `{}`, which yields no block rather
  /// than an empty one.
  static String? _formatArgs(String args) {
    final decoded = _tryDecodeObject(args);
    if (decoded == null) return args;
    if (decoded.isEmpty) return null;
    for (final key in _sourceKeys) {
      final value = decoded[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  static Map<String, dynamic>? _tryDecodeObject(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static String? _pickSource(SkillToolCallActivity activity) {
    for (final key in _sourceKeys) {
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
