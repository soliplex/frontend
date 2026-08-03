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
/// nothing to disclose, so a row's contents do not shift between its
/// disclosing and non-disclosing states.
const double _disclosureWidth = 14;

/// Size of a step row's status icon. The disclosure chevron beside it is
/// [_disclosureWidth], which is wider.
const double _statusIconSize = 12;

/// Lines of a source body shown before the reader asks for the rest. A
/// retrieval result runs to tens of thousands of characters, which would bury
/// every row after it. Clamped by line count rather than pixels so the clamp
/// holds the same shape at every text scale.
const int _collapsedSourceLines = 8;

/// Suffixes distinguishing the things a row can disclose, so each keys its own
/// entry in the expansion store. An activity row needs one even though it
/// discloses a single body: its own open/closed state is already keyed by the
/// bare `messageId`, and reusing that would make opening the row also unclamp
/// the body.
const String _argsClampSuffix = '#args';
const String _resultClampSuffix = '#result';
const String _contentClampSuffix = '#content';

/// The braces bounding a JSON object, so an empty one is recognised by scan
/// rather than by decoding it.
const int _leftBrace = 0x7B;
const int _rightBrace = 0x7D;

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
    final activities = widget.tracker.activities.watch(context);
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
              for (final entry in entries)
                _buildEntry(entry, theme, activities),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEntry(
    TimelineEntry entry,
    ThemeData theme,
    List<ActivityRecord> activities,
  ) {
    switch (entry) {
      case TimelineStep(:final activityIds):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _stepRow(entry, theme),
            for (final id in activityIds)
              if (_resolveActivity(id, activities) case final activity?)
                _activityRow(activity, theme, indent: _nestedIndent),
          ],
        );
      case TimelineStandaloneActivity(:final activityId):
        final activity = _resolveActivity(activityId, activities);
        if (activity == null) return const SizedBox.shrink();
        return _activityRow(activity, theme, indent: 0);
    }
  }

  /// Looks up the record for [id] among the tracker's [activities].
  /// Returns `null` for a dangling id so the renderer falls through to
  /// an empty row instead of throwing.
  ///
  /// A timeline id and its record arrive by two independent routes from
  /// one wire event: the tracker places the id when it observes an
  /// `ActivitySnapshot`, while the record arrives through the folded
  /// activity list the tracker mirrors. The routes cannot disagree over a
  /// malformed payload — both refuse a non-object `content` on the same
  /// test, so such an event yields neither an id nor a record. What is
  /// left is a frontend logic bug: a historical tracker handed a timeline
  /// and a record list built from different event streams. Logged at
  /// warning the first time each id fails so the dropped row is
  /// observable instead of silent.
  ActivityRecord? _resolveActivity(
    String id,
    List<ActivityRecord> activities,
  ) {
    for (final activity in activities) {
      if (activity.messageId == id) return activity;
    }
    if (_loggedDanglingIds.add(id)) {
      _logger.warning(
        'ExecutionTimeline: timeline references an activity id with no '
        'matching record; row hidden',
        attributes: {
          'activityId': id,
          'roomId': widget.roomId,
          'messageId': widget.messageId,
          'resolvableIdCount': activities.length,
        },
      );
    }
    return null;
  }

  Widget _stepRow(TimelineStep entry, ThemeData theme) {
    final step = entry.step;
    final id = entry.toolCallId;
    // Whether there is detail is decided without formatting it: this runs for
    // every row on every rebuild, and an args delta rebuilds the timeline.
    final hasArgs = entry.args.isNotEmpty && !_isEmptyArgsObject(entry.args);
    final result = (entry.result?.isEmpty ?? true) ? null : entry.result;
    // A server tool call's args and result are the call's own detail, so the
    // step expands in place. A step with no id carries no detail of its own and
    // keeps the slot only so icons stay column-aligned.
    final hasDetail = id != null && (hasArgs || result != null);
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
            if (hasArgs)
              _sourceBlock(
                _formatArgs(entry.args),
                theme,
                label: 'Arguments',
                clampId: '$id$_argsClampSuffix',
              ),
            // AG-UI carries no field for a failed outcome, so a tool that hit a
            // limit or raised delivers its message through the ordinary result
            // string. Rendering it is the only way that text reaches the user
            // in the chat UI.
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
    ActivityRecord activity,
    ThemeData theme, {
    required double indent,
  }) {
    final hasSource = activity.content.isNotEmpty;
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
                  width: _disclosureWidth,
                  child: hasSource
                      ? Icon(
                          isExpanded ? Icons.expand_more : Icons.chevron_right,
                          size: _disclosureWidth,
                          color: theme.colorScheme.onSurfaceVariant,
                        )
                      : const SizedBox.shrink(),
                ),
                // A nested row's `indent` already lands this chevron on the
                // step row's label, so no width is reserved for a status icon
                // here; reserving it would only gap the label out.
                const SizedBox(width: SoliplexSpacing.s2),
                Expanded(
                  child: _rowLabel(
                    _activityLabel(activity),
                    theme,
                    running: false,
                  ),
                ),
              ],
            ),
          ),
          if (hasSource && isExpanded)
            _sourceBlock(
              _encodeContent(activity.content),
              theme,
              clampId: '${activity.messageId}$_contentClampSuffix',
            ),
        ],
      ),
    );
  }

  /// A source block whose body clamps to [_collapsedSourceLines] until the
  /// reader asks for the rest.
  ///
  /// [clampId] keys that per block, so expanding one call's result leaves every
  /// other row alone. Every body here can run to tens of KB, so there is no
  /// unclamped path — one would bury every row below it.
  Widget _sourceBlock(
    String source,
    ThemeData theme, {
    required String clampId,
    String? label,
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

  Widget _sourceBody(String source, ThemeData theme, String clampId) {
    final style =
        context.monospaceOn(theme.textTheme.labelSmall).copyWith(height: 1.3);
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
            // A labelled control rather than a bare tap target, so it carries
            // button semantics and the design system's minimum tap target.
            if (overflows)
              SoliplexButton.text(
                onPressed: () => _toggleSource(clampId),
                isCompact: true,
                // The row disclosures elsewhere encode state (right when
                // closed, down when open) because they carry no words. This
                // one is labelled with a verb, so the arrow points at what the
                // tap does: down to reveal, up to collapse.
                icon: Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: _disclosureWidth,
                ),
                child: Text(expanded ? 'Show less' : 'Show more'),
              ),
          ],
        );
      },
    );
  }

  /// The primary label of a timeline row. While the row is [running] the text
  /// shimmers (a calmer signal than a per-row spinner) and settles back to
  /// the plain muted label — same resting color — once the step settles, on
  /// success or failure alike.
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

  /// Whether [source] needs more than [_collapsedSourceLines] to render at
  /// [maxWidth], and so warrants a disclosure control.
  ///
  /// Counts explicit line breaks first, which settles a raw retrieval result
  /// without measuring it: laying one out is a full line-break pass on the UI
  /// thread, repeated for every expanded block each time an args delta rebuilds
  /// the timeline. An encoded activity content does not always benefit —
  /// encoding escapes the newlines inside a string value, so a few-keyed
  /// payload wrapping tens of KB of chunk text arrives as a handful of physical
  /// lines and falls through to the wrap measurement below.
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

  /// Renders a tool call's accumulated `TOOL_CALL_ARGS` for display.
  ///
  /// Prefers the one field that carries the intent — the script, the code, the
  /// query, the command — over the whole object. Falls back to the raw string
  /// when it does not parse: while the call is still streaming the accumulation
  /// is a JSON prefix, and a partial payload is more useful shown than hidden.
  ///
  /// Called only for a row the reader has expanded, and only once
  /// [_isEmptyArgsObject] has ruled out the payload of a tool that takes no
  /// arguments — which is why every path here yields something to show.
  static String _formatArgs(String args) {
    final decoded = _tryDecodeObject(args);
    if (decoded == null) return args;
    for (final key in _sourceKeys) {
      final value = decoded[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return const JsonEncoder.withIndent('  ').convert(decoded);
  }

  /// Whether [args] is a JSON object with no members — what a tool that takes
  /// no arguments sends, and which yields no block rather than an empty one.
  ///
  /// Decided by scanning rather than by decoding because every step row asks
  /// this on every rebuild, expanded or not, and an args delta rebuilds the
  /// timeline. Bails at the first member, so a real payload costs a few
  /// character reads rather than a parse.
  static bool _isEmptyArgsObject(String args) {
    var index = _skipJsonSpace(args, 0);
    if (index == args.length || args.codeUnitAt(index) != _leftBrace) {
      return false;
    }
    index = _skipJsonSpace(args, index + 1);
    if (index == args.length || args.codeUnitAt(index) != _rightBrace) {
      return false;
    }
    return _skipJsonSpace(args, index + 1) == args.length;
  }

  static int _skipJsonSpace(String source, int from) {
    var index = from;
    while (index < source.length) {
      final unit = source.codeUnitAt(index);
      // The four code points JSON counts as insignificant whitespace.
      if (unit != 0x20 && unit != 0x09 && unit != 0x0A && unit != 0x0D) break;
      index++;
    }
    return index;
  }

  static Map<String, dynamic>? _tryDecodeObject(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// The row's label: any content carrying a non-empty `tool_name` string is
  /// labelled with it, and otherwise the activity type is the label. AG-UI names
  /// no vocabulary for what is inside an activity's content, so this is a
  /// legibility preference rather than a schema — a payload without the key
  /// renders under its type instead of losing its row.
  static String _activityLabel(ActivityRecord activity) {
    final toolName = activity.content['tool_name'];
    if (toolName is String && toolName.isNotEmpty) return toolName;
    return activity.activityType;
  }

  /// What an expanded row discloses: the whole content, which is all an opaque
  /// payload affords and loses nothing the record carried.
  ///
  /// Called only for a row the reader has expanded — `content` reaches tens of
  /// KB, so encoding it to decide whether to draw a chevron would cost that on
  /// every rebuild.
  static String _encodeContent(Map<String, dynamic> content) =>
      const JsonEncoder.withIndent('  ').convert(content);

  static String _formatDuration(Duration d) {
    final seconds = d.inMilliseconds / 1000;
    return '${seconds.toStringAsFixed(1)}s';
  }
}
