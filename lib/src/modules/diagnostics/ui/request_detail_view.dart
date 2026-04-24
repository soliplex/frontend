import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

import '../../../../soliplex_frontend.dart';
import '../../../shared/copy_button.dart';
import '../models/format_utils.dart';
import '../models/http_event_group.dart';
import '../models/search_text_extractor.dart';
import 'http_status_display.dart';
import 'overview_tab.dart';

/// Scope options for cross-tab text search.
enum SearchScope {
  everything('Everything'),
  request('Request'),
  response('Response'),
  curl('curl'),
  overview('Overview');

  const SearchScope(this.label);

  final String label;
}

/// Displays detailed request/response information in a tabbed view.
///
/// Tabs:
/// - Request: Method, URL, headers, body
/// - Response: Status, headers, body
/// - curl: Generated curl command for reproduction
/// - Overview: Structured JSON and SSE conversation view
class RequestDetailView extends StatefulWidget {
  const RequestDetailView({required this.group, super.key});

  final HttpEventGroup group;

  @override
  State<RequestDetailView> createState() => _RequestDetailViewState();
}

class _RequestDetailViewState extends State<RequestDetailView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchController = TextEditingController();
  SearchScope _scope = SearchScope.everything;
  int _currentMatchIndex = 0;

  static const _tabCount = 4;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() => setState(() => _currentMatchIndex = 0);

  String _curlText() => group.toCurl() ?? '';

  HttpEventGroup get group => widget.group;

  int _matchesForScope(SearchScope scope) {
    final q = _searchController.text;
    return switch (scope) {
      SearchScope.request => countMatches(extractRequestText(group), q),
      SearchScope.response => countMatches(extractResponseText(group), q),
      SearchScope.curl => countMatches(_curlText(), q),
      SearchScope.overview => countMatches(extractOverviewText(group), q),
      SearchScope.everything => 0,
    };
  }

  int _tabMatches(int tabIndex) {
    final q = _searchController.text;
    if (q.isEmpty) return 0;
    final tabScope = switch (tabIndex) {
      0 => SearchScope.request,
      1 => SearchScope.response,
      2 => SearchScope.curl,
      3 => SearchScope.overview,
      _ => SearchScope.request,
    };
    if (_scope != SearchScope.everything && _scope != tabScope) return 0;
    return _matchesForScope(tabScope);
  }

  List<int> get _matchCountsPerTab => [
        _matchesForScope(SearchScope.request),
        _matchesForScope(SearchScope.response),
        _matchesForScope(SearchScope.curl),
        _matchesForScope(SearchScope.overview),
      ];

  int get _totalMatches {
    final q = _searchController.text;
    if (q.isEmpty) return 0;
    if (_scope == SearchScope.everything) {
      return _matchCountsPerTab.fold(0, (a, b) => a + b);
    }
    return _matchesForScope(_scope);
  }

  void _nextMatch() {
    if (_totalMatches == 0) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex + 1) % _totalMatches;
      _navigateToMatch();
    });
  }

  void _previousMatch() {
    if (_totalMatches == 0) return;
    setState(() {
      _currentMatchIndex =
          (_currentMatchIndex - 1 + _totalMatches) % _totalMatches;
      _navigateToMatch();
    });
  }

  void _navigateToMatch() {
    if (_scope != SearchScope.everything) return;
    final counts = _matchCountsPerTab;
    var remaining = _currentMatchIndex;
    for (var i = 0; i < counts.length; i++) {
      if (remaining < counts[i]) {
        if (_tabController.index != i) {
          _tabController.animateTo(i);
        }
        return;
      }
      remaining -= counts[i];
    }
  }

  Widget _buildTab(String label, int tabIndex) {
    final count = _tabMatches(tabIndex);
    if (count == 0) return Tab(text: label);
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          const SizedBox(width: SoliplexSpacing.s1),
          _MatchBadge(count: count),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SoliplexSpacing.s3, vertical: SoliplexSpacing.s2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search…',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => _searchController.clear(),
                        tooltip: 'Clear search',
                      )
                    : null,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: SoliplexSpacing.s2),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: SoliplexSpacing.s2),
          DropdownButton<SearchScope>(
            value: _scope,
            underline: const SizedBox.shrink(),
            isDense: true,
            onChanged: (v) {
              if (v != null) {
                setState(() {
                  _scope = v;
                  _currentMatchIndex = 0;
                });
              }
            },
            items: [
              for (final scope in SearchScope.values)
                DropdownMenuItem(
                  value: scope,
                  child: Text(scope.label),
                ),
            ],
          ),
          if (_searchController.text.isNotEmpty && _totalMatches > 0) ...[
            const SizedBox(width: SoliplexSpacing.s2),
            Text(
              '${_currentMatchIndex + 1}/$_totalMatches',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up, size: 20),
              onPressed: _previousMatch,
              tooltip: 'Previous match',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                  minWidth: SoliplexSpacing.s8, minHeight: SoliplexSpacing.s8),
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, size: 20),
              onPressed: _nextMatch,
              tooltip: 'Next match',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                  minWidth: SoliplexSpacing.s8, minHeight: SoliplexSpacing.s8),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _MethodBadge(
                method: group.methodLabel,
                isStream: group.isStream,
              ),
              const SizedBox(width: SoliplexSpacing.s2),
              Expanded(child: HttpStatusDisplay(group: group)),
              Text(
                group.timestamp.toHttpTimeString(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: SoliplexSpacing.s2),
          SelectableText(
            group.uri.toString(),
            style: SoliplexTheme.mergeCode(context, theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSummaryHeader(context),
        _buildSearchBar(context),
        TabBar(
          controller: _tabController,
          tabs: [
            _buildTab('Request', 0),
            _buildTab('Response', 1),
            _buildTab('curl', 2),
            _buildTab('Overview', 3),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _RequestTab(group: group),
              _ResponseTab(group: group),
              _CurlTab(group: group),
              OverviewTab(group: group),
            ],
          ),
        ),
      ],
    );
  }
}

class _MatchBadge extends StatelessWidget {
  const _MatchBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SoliplexSpacing.s2, vertical: SoliplexSpacing.s1),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: colorScheme.onPrimaryContainer,
        ),
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
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = isStream
        ? colorScheme.secondaryContainer
        : colorScheme.primaryContainer;
    final textColor = isStream
        ? colorScheme.onSecondaryContainer
        : colorScheme.onPrimaryContainer;

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SoliplexSpacing.s2, vertical: SoliplexSpacing.s1),
      decoration: BoxDecoration(
        color: backgroundColor,
      ),
      child: Text(
        method,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          color: textColor,
        ),
      ),
    );
  }
}

class _RequestTab extends StatelessWidget {
  const _RequestTab({required this.group});

  final HttpEventGroup group;

  @override
  Widget build(BuildContext context) {
    final headers = group.requestHeaders;
    final body = group.requestBody;

    if (headers.isEmpty && body == null) {
      return const _EmptyTabContent(message: 'No request headers or body');
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (headers.isNotEmpty) ...[
          _SectionHeader(
            title: 'Headers',
            copyButton: CopyButton(
              iconSize: 18,
              text:
                  headers.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
              tooltip: 'Copy Headers',
            ),
          ),
          _HeadersTable(headers: headers),
          const SizedBox(height: SoliplexSpacing.s4),
        ],
        if (body != null) ...[
          _SectionHeader(
            title: 'Body',
            copyButton: CopyButton(
              iconSize: 18,
              text: HttpEventGroup.formatBody(body),
              tooltip: 'Copy Body',
            ),
          ),
          _BodyDisplay(body: body),
        ],
      ],
    );
  }
}

class _ResponseTab extends StatelessWidget {
  const _ResponseTab({required this.group});

  final HttpEventGroup group;

  @override
  Widget build(BuildContext context) {
    if (group.isStream) {
      return _buildStreamResponse(context);
    }

    final response = group.response;
    final error = group.error;

    if (response == null && error == null) {
      return const _EmptyTabContent(message: 'Waiting for response...');
    }

    if (error != null) {
      return _buildErrorResponse(error);
    }

    return _buildNormalResponse(response!);
  }

  Widget _buildStreamResponse(BuildContext context) {
    final streamEnd = group.streamEnd;
    if (streamEnd == null) {
      return const _EmptyTabContent(message: 'Stream in progress...');
    }

    if (streamEnd.error != null) {
      return _ErrorDisplay(
        message: streamEnd.error!.message,
        details: 'Duration: ${streamEnd.duration.toHttpDurationString()}\n'
            'Bytes received: ${streamEnd.bytesReceived.toHttpBytesString()}',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MetadataRow(
          label: 'Duration',
          value: streamEnd.duration.toHttpDurationString(),
        ),
        _MetadataRow(
          label: 'Bytes Received',
          value: streamEnd.bytesReceived.toHttpBytesString(),
        ),
        if (streamEnd.body != null) ...[
          const SizedBox(height: SoliplexSpacing.s4),
          _SectionHeader(
            title: 'Stream Content',
            copyButton: CopyButton(
              iconSize: 18,
              text: streamEnd.body!,
              tooltip: 'Copy Stream Content',
            ),
          ),
          _BodyDisplay(body: streamEnd.body),
        ],
      ],
    );
  }

  Widget _buildErrorResponse(HttpErrorEvent error) {
    return _ErrorDisplay(
      message: error.exception.message,
      details: 'Type: ${error.exception.runtimeType}\n'
          'Duration: ${error.duration.toHttpDurationString()}',
    );
  }

  Widget _buildNormalResponse(HttpResponseEvent resp) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MetadataRow(label: 'Status', value: '${resp.statusCode}'),
        if (resp.reasonPhrase != null)
          _MetadataRow(label: 'Reason', value: resp.reasonPhrase!),
        _MetadataRow(
          label: 'Duration',
          value: resp.duration.toHttpDurationString(),
        ),
        _MetadataRow(
          label: 'Size',
          value: resp.bodySize.toHttpBytesString(),
        ),
        if (resp.headers != null && resp.headers!.isNotEmpty) ...[
          const SizedBox(height: SoliplexSpacing.s4),
          _SectionHeader(
            title: 'Headers',
            copyButton: CopyButton(
              iconSize: 18,
              text: resp.headers!.entries
                  .map((e) => '${e.key}: ${e.value}')
                  .join('\n'),
              tooltip: 'Copy Headers',
            ),
          ),
          _HeadersTable(headers: resp.headers!),
        ],
        if (resp.body != null) ...[
          const SizedBox(height: SoliplexSpacing.s4),
          _SectionHeader(
            title: 'Body',
            copyButton: CopyButton(
              iconSize: 18,
              text: HttpEventGroup.formatBody(resp.body),
              tooltip: 'Copy Body',
            ),
          ),
          _BodyDisplay(body: resp.body),
        ],
      ],
    );
  }
}

class _CurlTab extends StatelessWidget {
  const _CurlTab({required this.group});

  final HttpEventGroup group;

  @override
  Widget build(BuildContext context) {
    final curl = group.toCurl();
    if (curl == null) {
      return const _EmptyTabContent(
        message: 'curl command unavailable - no request data',
      );
    }

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'curl command',
                style: theme.textTheme.titleSmall,
              ),
              const Spacer(),
              CopyButton(
                  iconSize: 18, text: curl, tooltip: 'Copy to clipboard'),
            ],
          ),
          const SizedBox(height: SoliplexSpacing.s2),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
              ),
              child: SelectableText(
                curl,
                style:
                    SoliplexTheme.mergeCode(context, theme.textTheme.bodySmall),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.copyButton});

  final String title;
  final Widget? copyButton;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const Spacer(),
          if (copyButton != null) copyButton!,
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

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
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
                      style: SoliplexTheme.mergeCode(
                        context,
                        theme.textTheme.bodySmall,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: SoliplexSpacing.s2),
                  Expanded(
                    child: SelectableText(
                      entry.value,
                      style: SoliplexTheme.mergeCode(
                        context,
                        theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BodyDisplay extends StatelessWidget {
  const _BodyDisplay({required this.body});

  final dynamic body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formattedBody = HttpEventGroup.formatBody(body);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
      ),
      child: SelectableText(
        formattedBody,
        style: SoliplexTheme.mergeCode(context, theme.textTheme.bodySmall),
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTabContent extends StatelessWidget {
  const _EmptyTabContent({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        message,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ErrorDisplay extends StatelessWidget {
  const _ErrorDisplay({required this.message, this.details});

  final String message;
  final String? details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: colorScheme.error),
          const SizedBox(height: SoliplexSpacing.s3),
          Text(
            message,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.error,
            ),
            textAlign: TextAlign.center,
          ),
          if (details != null) ...[
            const SizedBox(height: SoliplexSpacing.s2),
            Text(
              details!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
