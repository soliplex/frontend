import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../soliplex_frontend.dart';
import '../models/event_accumulator.dart';
import '../models/http_event_group.dart';
import '../models/json_tree_model.dart';
import '../models/sse_event_parser.dart';
import 'json_tree_view.dart';

/// Structured overview of an [HttpEventGroup]: request body as a JSON tree,
/// and for SSE streams a conversation/events toggle.
class OverviewTab extends StatefulWidget {
  const OverviewTab({required this.group, super.key});

  final HttpEventGroup group;

  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<OverviewTab> {
  _StreamView _streamView = _StreamView.conversation;
  SseParseResult? _parseResult;
  AccumulatedRun? _accumulatedRun;

  SseParseResult _getParsed() {
    return _parseResult ??= parseSseEvents(widget.group.streamEnd!.body!);
  }

  AccumulatedRun _getAccumulated() {
    return _accumulatedRun ??= accumulateEvents(_getParsed().events);
  }

  dynamic get _responseBody {
    final response = widget.group.response;
    if (response != null && response.body != null) return response.body;
    final streamEnd = widget.group.streamEnd;
    if (streamEnd != null && streamEnd.body != null) return streamEnd.body;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final body = group.requestBody;
    final hasRequestBody = body != null && body.toString().isNotEmpty;

    if (!hasRequestBody && !group.isStream && _responseBody == null) {
      return _emptyState(context);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (hasRequestBody) ...[
          _JsonSection(title: 'Request Body', body: body),
          const SizedBox(height: SoliplexSpacing.s4),
        ],
        if (group.isStream)
          _StreamSection(
            parseResult: _getParsed(),
            accumulatedRun: _getAccumulated(),
            view: _streamView,
            onViewChanged: (v) => setState(() => _streamView = v),
          )
        else if (_responseBody != null) ...[
          _JsonSection(title: 'Response Body', body: _responseBody),
        ],
      ],
    );
  }

  Widget _emptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        'No structured content available',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

enum _StreamView { conversation, events }

class _StreamSection extends StatelessWidget {
  const _StreamSection({
    required this.parseResult,
    required this.accumulatedRun,
    required this.view,
    required this.onViewChanged,
  });

  final SseParseResult parseResult;
  final AccumulatedRun accumulatedRun;
  final _StreamView view;
  final ValueChanged<_StreamView> onViewChanged;

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
            SegmentedButton<_StreamView>(
              segments: const [
                ButtonSegment(
                  value: _StreamView.conversation,
                  label: Text('Conversation'),
                ),
                ButtonSegment(
                  value: _StreamView.events,
                  label: Text('Events'),
                ),
              ],
              selected: {view},
              onSelectionChanged: (s) => onViewChanged(s.first),
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: SoliplexSpacing.s2),
        if (parseResult.wasTruncated) _TruncationBanner(),
        if (view == _StreamView.conversation)
          _ConversationView(run: accumulatedRun)
        else
          _EventsView(events: parseResult.events),
      ],
    );
  }
}

class _TruncationBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(
          horizontal: SoliplexSpacing.s3, vertical: SoliplexSpacing.s2),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
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
            style: TextStyle(
              fontSize: 12,
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
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RoleBadge(
                label: label, color: badgeColor, textColor: badgeTextColor),
            if (content.isNotEmpty) ...[
              const SizedBox(height: SoliplexSpacing.s2),
              SelectableText(
                content,
                style: theme.textTheme.bodySmall,
              ),
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
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SoliplexSpacing.s2, vertical: SoliplexSpacing.s1),
      decoration: BoxDecoration(
        color: color,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
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
      margin: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: SoliplexSpacing.s3, vertical: SoliplexSpacing.s2),
              child: Row(
                children: [
                  _EventTypeBadge(type: widget.event.type),
                  const SizedBox(width: SoliplexSpacing.s2),
                  if (summary.isNotEmpty)
                    Expanded(
                      child: Text(
                        summary,
                        style: SoliplexTheme.mergeCode(
                          context,
                          theme.textTheme.bodySmall,
                        ).copyWith(color: colorScheme.onSurfaceVariant),
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
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SoliplexSpacing.s2, vertical: SoliplexSpacing.s1),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
      ),
      child: Text(
        type,
        style: SoliplexTheme.codeStyle(context).copyWith(
          fontSize: 10,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Renders [body] as a JSON tree if parseable, otherwise as plain text.
class _JsonSection extends StatelessWidget {
  const _JsonSection({required this.title, required this.body});

  final String title;
  final dynamic body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    dynamic parsed;
    String? plainText;

    if (body is String) {
      try {
        parsed = jsonDecode(body as String);
      } on FormatException {
        plainText = body as String;
      }
    } else {
      parsed = body;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: SoliplexSpacing.s2),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          child: plainText != null
              ? SelectableText(
                  plainText,
                  style: SoliplexTheme.mergeCode(
                    context,
                    theme.textTheme.bodySmall,
                  ),
                )
              : JsonTreeView(nodes: buildJsonTree(parsed)),
        ),
      ],
    );
  }
}
