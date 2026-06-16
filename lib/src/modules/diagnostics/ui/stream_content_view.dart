import 'package:flutter/material.dart';

import 'package:soliplex_design/soliplex_design.dart';
import '../models/event_accumulator.dart';
import '../models/json_tree_model.dart';
import '../models/sse_event_parser.dart';
import 'json_tree_view.dart';

/// How the parsed SSE stream is rendered.
enum StreamView {
  /// Accumulated, human-readable conversation (messages, tool calls, …).
  conversation('Conversation'),

  /// The raw list of individual SSE events.
  events('Events'),

  /// The unparsed stream payload.
  raw('Raw');

  const StreamView(this.label);

  final String label;
}

/// Renders an SSE stream body as a conversation, an event list, or the raw
/// payload, with a segmented switch between them.
///
/// Extracted from the old Overview tab so the Response section of an HTTP
/// exchange can host the structured stream views inline.
class StreamContentView extends StatefulWidget {
  const StreamContentView({required this.body, super.key});

  /// The raw SSE stream payload.
  final String body;

  @override
  State<StreamContentView> createState() => _StreamContentViewState();
}

class _StreamContentViewState extends State<StreamContentView> {
  StreamView _view = StreamView.conversation;
  SseParseResult? _parseResult;
  AccumulatedRun? _accumulatedRun;

  SseParseResult get _parsed => _parseResult ??= parseSseEvents(widget.body);

  AccumulatedRun get _accumulated =>
      _accumulatedRun ??= accumulateEvents(_parsed.events);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Stream', style: theme.textTheme.titleSmall),
            const Spacer(),
            SegmentedButton<StreamView>(
              segments: [
                for (final v in StreamView.values)
                  ButtonSegment(value: v, label: Text(v.label)),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: SoliplexSpacing.s2),
        if (_parsed.wasTruncated) const _TruncationBanner(),
        switch (_view) {
          StreamView.conversation => _ConversationView(run: _accumulated),
          StreamView.events => _EventsView(events: _parsed.events),
          StreamView.raw => _RawStreamView(body: widget.body),
        },
      ],
    );
  }
}

class _RawStreamView extends StatelessWidget {
  const _RawStreamView({required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SoliplexSpacing.s3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(soliplexRadii.sm),
      ),
      child: SelectableText(
        body.isEmpty ? '(empty)' : body,
        style: context.monospaceOn(theme.textTheme.bodySmall),
      ),
    );
  }
}

class _TruncationBanner extends StatelessWidget {
  const _TruncationBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: SoliplexSpacing.s2),
      padding: const EdgeInsets.symmetric(
        horizontal: SoliplexSpacing.s3,
        vertical: SoliplexSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(soliplexRadii.sm),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: SoliplexSpacing.s2),
          Text(
            'Earlier stream content was truncated',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onTertiaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationView extends StatelessWidget {
  const _ConversationView({required this.run});

  final AccumulatedRun run;

  @override
  Widget build(BuildContext context) {
    if (run.entries.isEmpty) {
      return _emptyMessage(context, 'No conversation entries');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in run.entries) _RunEntryCard(entry: entry),
      ],
    );
  }

  Widget _emptyMessage(BuildContext context, String message) {
    return Center(
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _RunEntryCard extends StatelessWidget {
  const _RunEntryCard({required this.entry});

  final RunEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final (label, badgeColor, badgeTextColor, content) = switch (entry) {
      MessageEntry(:final role, :final text) => (
          role.toUpperCase(),
          role == 'user'
              ? colorScheme.primaryContainer
              : colorScheme.secondaryContainer,
          role == 'user'
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSecondaryContainer,
          text,
        ),
      ToolCallEntry(:final toolName, :final args) => (
          'TOOL CALL',
          colorScheme.tertiaryContainer,
          colorScheme.onTertiaryContainer,
          '$toolName\n$args',
        ),
      ToolResultEntry(:final content) => (
          'TOOL RESULT',
          colorScheme.surfaceContainerHighest,
          colorScheme.onSurface,
          content,
        ),
      ThinkingEntry(:final text) => (
          'THINKING',
          colorScheme.surfaceContainerLow,
          colorScheme.onSurfaceVariant,
          text,
        ),
      RunStatusEntry(:final type, :final message) => (
          type,
          colorScheme.surfaceContainerLow,
          colorScheme.onSurfaceVariant,
          message ?? '',
        ),
      StateEntry(:final type, :final data) => (
          type,
          colorScheme.surfaceContainerLow,
          colorScheme.onSurfaceVariant,
          data?.toString() ?? '',
        ),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: SoliplexSpacing.s2),
      child: Padding(
        padding: const EdgeInsets.all(SoliplexSpacing.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RoleBadge(
              label: label,
              color: badgeColor,
              textColor: badgeTextColor,
            ),
            if (content.isNotEmpty) ...[
              const SizedBox(height: SoliplexSpacing.s2),
              SelectableText(content, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SoliplexSpacing.s2,
        vertical: SoliplexSpacing.s1,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(soliplexRadii.sm),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }
}

class _EventsView extends StatelessWidget {
  const _EventsView({required this.events});

  final List<SseEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Center(
        child: Text(
          'No events',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final event in events) _SseEventCard(event: event),
      ],
    );
  }
}

class _SseEventCard extends StatefulWidget {
  const _SseEventCard({required this.event});

  final SseEvent event;

  @override
  State<_SseEventCard> createState() => _SseEventCardState();
}

class _SseEventCardState extends State<_SseEventCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final summary = sseEventSummary(widget.event);
    final nodes = buildJsonTree(widget.event.payload);

    return Card(
      margin: const EdgeInsets.only(bottom: SoliplexSpacing.s2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SoliplexSpacing.s3,
                vertical: SoliplexSpacing.s2,
              ),
              child: Row(
                children: [
                  _EventTypeBadge(type: widget.event.type),
                  const SizedBox(width: SoliplexSpacing.s2),
                  if (summary.isNotEmpty)
                    Expanded(
                      child: Text(
                        summary,
                        style: context
                            .monospaceOn(theme.textTheme.bodySmall)
                            .copyWith(color: colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SoliplexSpacing.s3,
                0,
                SoliplexSpacing.s3,
                SoliplexSpacing.s3,
              ),
              child: JsonTreeView(nodes: nodes),
            ),
        ],
      ),
    );
  }
}

class _EventTypeBadge extends StatelessWidget {
  const _EventTypeBadge({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SoliplexSpacing.s2,
        vertical: SoliplexSpacing.s1,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(soliplexRadii.sm),
      ),
      child: Text(
        type,
        style: context
            .monospaceOn(theme.textTheme.labelSmall)
            .copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}
