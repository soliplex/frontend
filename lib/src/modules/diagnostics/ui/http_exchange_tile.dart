import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:soliplex_design/soliplex_design.dart';
import '../../../shared/copy_button.dart';
import '../models/format_utils.dart';
import '../models/http_event_group.dart';
import '../models/json_tree_model.dart';
import 'http_event_tile.dart';
import 'http_status_display.dart';
import 'json_tree_view.dart';
import 'stream_content_view.dart';

/// One HTTP exchange rendered as an expandable row.
///
/// Collapsed it shows a compact summary line (method · endpoint · status);
/// expanded it reveals a key-value summary grid, the request, and the
/// response — replacing the old split-view + tabbed detail. The same
/// metadata is shown in exactly one place: the summary grid is canonical, so
/// the request/response sections carry only headers and bodies.
class HttpExchangeTile extends StatefulWidget {
  const HttpExchangeTile({
    required this.group,
    this.tabular = false,
    this.initiallyExpanded = false,
    super.key,
  });

  final HttpEventGroup group;

  /// When true the collapsed row is a single dense line (desktop/tablet);
  /// otherwise it falls back to the stacked two-line tile (mobile).
  final bool tabular;

  final bool initiallyExpanded;

  @override
  State<HttpExchangeTile> createState() => _HttpExchangeTileState();
}

class _HttpExchangeTileState extends State<HttpExchangeTile> {
  late bool _expanded = widget.initiallyExpanded;

  HttpEventGroup get group => widget.group;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: _toggle,
          child: widget.tabular ? _tabularHeader(context) : _stackedHeader(),
        ),
        if (_expanded) _ExchangeDetail(group: group),
      ],
    );
  }

  Widget _chevron(BuildContext context) => Icon(
        _expanded ? Icons.expand_less : Icons.expand_more,
        size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );

  Widget _stackedHeader() {
    return Row(
      children: [
        Expanded(child: HttpEventTile(group: group)),
        Padding(
          padding: const EdgeInsets.only(right: SoliplexSpacing.s2),
          child: _chevron(context),
        ),
      ],
    );
  }

  Widget _tabularHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SoliplexSpacing.s3,
        vertical: SoliplexSpacing.s2,
      ),
      child: Row(
        children: [
          _MethodBadge(method: group.methodLabel, isStream: group.isStream),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: Text(
              group.pathWithQuery,
              style: context.monospaceOn(theme.textTheme.bodySmall),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: SoliplexSpacing.s3),
          Text(
            group.timestamp.toHttpTimeString(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: SoliplexSpacing.s3),
          HttpStatusDisplay(group: group),
          const SizedBox(width: SoliplexSpacing.s2),
          _chevron(context),
        ],
      ),
    );
  }
}

/// The expanded body: summary grid, request, response, and a curl action.
class _ExchangeDetail extends StatelessWidget {
  const _ExchangeDetail({required this.group});

  final HttpEventGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final curl = group.toCurl();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SoliplexSpacing.s4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummarySection(group: group),
          const SizedBox(height: SoliplexSpacing.s6),
          _RequestSection(group: group),
          const SizedBox(height: SoliplexSpacing.s6),
          _ResponseSection(group: group),
          if (curl != null) ...[
            const SizedBox(height: SoliplexSpacing.s4),
            Align(
              alignment: Alignment.centerLeft,
              child: SoliplexButton.text(
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () => _copyCurl(context, curl),
                child: const Text('Copy as curl'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _copyCurl(BuildContext context, String curl) {
    Clipboard.setData(ClipboardData(text: curl));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('curl command copied')),
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.group});

  final HttpEventGroup group;

  List<(String, String)> _entries() {
    final entries = <(String, String)>[
      ('Method', group.methodLabel),
    ];

    final response = group.response;
    final error = group.error;
    final streamEnd = group.streamEnd;

    if (response != null) {
      final status = response.reasonPhrase != null
          ? '${response.statusCode} ${response.reasonPhrase}'
          : '${response.statusCode}';
      entries
        ..add(('Status', status))
        ..add(('Duration', response.duration.toHttpDurationString()))
        ..add(('Size', response.bodySize.toHttpBytesString()));
    } else if (streamEnd != null) {
      entries
        ..add(('Stream', 'true'))
        ..add(('Duration', streamEnd.duration.toHttpDurationString()))
        ..add(('Received', streamEnd.bytesReceived.toHttpBytesString()));
    } else if (error != null) {
      entries
        ..add(('Error', '${error.exception.runtimeType}'))
        ..add(('Duration', error.duration.toHttpDurationString()));
    }

    if (group.hasTimestamp) {
      entries.add(('Started', group.timestamp.toHttpTimeString()));
    }

    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: 'Summary',
          trailing: CopyButton(
            iconSize: 18,
            text: group.uri.toString(),
            tooltip: 'Copy URL',
          ),
        ),
        SelectableText(
          group.uri.toString(),
          style: context.monospaceOn(theme.textTheme.bodySmall),
        ),
        const SizedBox(height: SoliplexSpacing.s3),
        _KvGrid(entries: _entries()),
      ],
    );
  }
}

class _RequestSection extends StatelessWidget {
  const _RequestSection({required this.group});

  final HttpEventGroup group;

  @override
  Widget build(BuildContext context) {
    final headers = group.requestHeaders;
    final body = group.requestBody;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'Request'),
        if (headers.isEmpty && body == null)
          const _EmptyHint(message: 'No request headers or body')
        else ...[
          if (headers.isNotEmpty) ...[
            _SubHeader(
              title: 'Headers',
              copyText:
                  headers.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
            ),
            _HeadersTable(headers: headers),
          ],
          if (body != null) ...[
            if (headers.isNotEmpty) const SizedBox(height: SoliplexSpacing.s4),
            _SubHeader(
              title: 'Body',
              copyText: HttpEventGroup.formatBody(body),
            ),
            _BodyView(body: body),
          ],
        ],
      ],
    );
  }
}

class _ResponseSection extends StatelessWidget {
  const _ResponseSection({required this.group});

  final HttpEventGroup group;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'Response'),
        _content(context),
      ],
    );
  }

  Widget _content(BuildContext context) {
    if (group.isStream) {
      final streamEnd = group.streamEnd;
      if (streamEnd == null) {
        return const _EmptyHint(message: 'Stream in progress…');
      }
      if (streamEnd.error != null) {
        return _ErrorDisplay(message: streamEnd.error!.message);
      }
      final body = streamEnd.body;
      if (body == null || body.isEmpty) {
        return const _EmptyHint(message: 'Stream completed with no content');
      }
      return StreamContentView(body: body);
    }

    final response = group.response;
    final error = group.error;

    if (error != null) {
      return _ErrorDisplay(message: error.exception.message);
    }
    if (response == null) {
      return const _EmptyHint(message: 'Waiting for response…');
    }

    final headers = response.headers ?? const <String, String>{};
    final body = response.body;

    if (headers.isEmpty && body == null) {
      return const _EmptyHint(message: 'No response headers or body');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (headers.isNotEmpty) ...[
          _SubHeader(
            title: 'Headers',
            copyText:
                headers.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
          ),
          _HeadersTable(headers: headers),
        ],
        if (body != null) ...[
          if (headers.isNotEmpty) const SizedBox(height: SoliplexSpacing.s4),
          _SubHeader(
            title: 'Body',
            copyText: HttpEventGroup.formatBody(body),
          ),
          _BodyView(body: body),
        ],
      ],
    );
  }
}

/// A request/response body shown as a structured JSON tree or raw text, with
/// a toggle when the payload parses as JSON. Replaces the old separate
/// "Overview" tab — raw vs. structured is a rendering mode, not a category.
class _BodyView extends StatefulWidget {
  const _BodyView({required this.body});

  final dynamic body;

  @override
  State<_BodyView> createState() => _BodyViewState();
}

enum _BodyMode { structured, raw }

class _BodyViewState extends State<_BodyView> {
  _BodyMode _mode = _BodyMode.structured;

  /// The parsed JSON value, or null when the body isn't JSON.
  dynamic get _parsed {
    final body = widget.body;
    if (body is String) {
      try {
        return jsonDecode(body);
      } on FormatException {
        return null;
      }
    }
    return body;
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parsed;
    final structurable = parsed != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (structurable) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<_BodyMode>(
              segments: const [
                ButtonSegment(value: _BodyMode.structured, label: Text('JSON')),
                ButtonSegment(value: _BodyMode.raw, label: Text('Raw')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
          ),
          const SizedBox(height: SoliplexSpacing.s2),
        ],
        _CodeSurface(
          child: structurable && _mode == _BodyMode.structured
              ? JsonTreeView(nodes: buildJsonTree(parsed))
              : SelectableText(
                  HttpEventGroup.formatBody(widget.body),
                  style: context.monospaceOn(
                    Theme.of(context).textTheme.bodySmall,
                  ),
                ),
        ),
      ],
    );
  }
}

class _CodeSurface extends StatelessWidget {
  const _CodeSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SoliplexSpacing.s3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(context.radii.sm),
      ),
      child: child,
    );
  }
}

class _KvGrid extends StatelessWidget {
  const _KvGrid({required this.entries});

  final List<(String, String)> entries;

  static const _cellWidth = 220.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: SoliplexSpacing.s6,
      runSpacing: SoliplexSpacing.s2,
      children: [
        for (final (key, value) in entries)
          SizedBox(
            width: _cellWidth,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 84,
                  child: Text(
                    key,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: SoliplexSpacing.s2),
                Expanded(
                  child: SelectableText(
                    value,
                    style: context.monospaceOn(theme.textTheme.bodySmall),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SoliplexSpacing.s2),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _SubHeader extends StatelessWidget {
  const _SubHeader({required this.title, required this.copyText});

  final String title;
  final String copyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: SoliplexSpacing.s2),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          CopyButton(iconSize: 18, text: copyText, tooltip: 'Copy $title'),
        ],
      ),
    );
  }
}

class _HeadersTable extends StatelessWidget {
  const _HeadersTable({required this.headers});

  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final monoSmall = context.monospaceOn(theme.textTheme.bodySmall);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(context.radii.sm),
      ),
      child: Column(
        children: [
          for (final (index, entry) in headers.entries.indexed)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: SoliplexSpacing.s3,
                vertical: SoliplexSpacing.s2,
              ),
              decoration: BoxDecoration(
                color: index.isEven
                    ? colorScheme.surfaceContainerLow
                    : colorScheme.surface,
                border: index > 0
                    ? Border(
                        top: BorderSide(color: colorScheme.outlineVariant),
                      )
                    : null,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 140,
                    child: SelectableText(
                      entry.key,
                      style: monoSmall.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: SoliplexSpacing.s2),
                  Expanded(
                    child: SelectableText(entry.value, style: monoSmall),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MethodBadge extends StatelessWidget {
  const _MethodBadge({required this.method, required this.isStream});

  final String method;
  final bool isStream;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final backgroundColor = isStream
        ? colorScheme.secondaryContainer
        : colorScheme.primaryContainer;
    final textColor = isStream
        ? colorScheme.onSecondaryContainer
        : colorScheme.onPrimaryContainer;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SoliplexSpacing.s2,
        vertical: SoliplexSpacing.s1,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(context.radii.sm),
      ),
      child: Text(
        method,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      message,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _ErrorDisplay extends StatelessWidget {
  const _ErrorDisplay({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SoliplexSpacing.s3),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(context.radii.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline,
              size: 18, color: colorScheme.onErrorContainer),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: SelectableText(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
