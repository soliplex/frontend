import 'package:flutter/material.dart';

import 'package:soliplex_design/soliplex_design.dart';

import '../models/http_category.dart';
import '../models/http_event_group.dart';
import '../models/http_event_grouper.dart';
import '../models/run_event_filter.dart';
import '../network_inspector.dart';
import 'concurrency_summary_panel.dart';
import 'http_exchange_tile.dart';

/// Status buckets for the request list's quick filter. `pending`/`streaming`
/// in-flight exchanges only show under [all].
enum _StatusFilter { all, success, errors }

/// Category buckets, mapped onto [HttpCategory] (with an `all` passthrough).
enum _CategoryFilter { all, llm, auth, system }

/// The captured HTTP exchanges, newest first, with the filters that narrow
/// them.
///
/// Stateful because the search and bucket filters are the pane's own concern:
/// changing one rebuilds the list without disturbing the screen's chrome. They
/// reset when the pane is swapped out, which the run filter deliberately does
/// not — see [runId].
///
/// Reads [inspector] in `build` without listening to it: the screen wraps this
/// pane in a `ListenableBuilder`, so a new instance arrives on every captured
/// event. Mounting it anywhere without that wrapper would leave it stale.
class RequestsPane extends StatefulWidget {
  const RequestsPane({
    required this.inspector,
    required this.onRunFilterCleared,
    this.runId,
    super.key,
  });

  final NetworkInspector inspector;

  /// When set (via the per-message deep link), the list is scoped to this agent
  /// run and shows a removable chip. Owned by the screen, because dismissing it
  /// has to survive a switch to the Logs pane and back.
  final String? runId;

  /// Called when the user dismisses the run chip. Required even though [runId]
  /// is nullable: a scoped list with no way to unscope it is a dead end, with
  /// a disabled chip and a "Clear filters" button that cannot clear.
  final VoidCallback onRunFilterCleared;

  @override
  State<RequestsPane> createState() => _RequestsPaneState();
}

class _RequestsPaneState extends State<RequestsPane> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  _StatusFilter _statusFilter = _StatusFilter.all;
  _CategoryFilter _categoryFilter = _CategoryFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _filterActive =>
      _searchQuery.isNotEmpty ||
      _statusFilter != _StatusFilter.all ||
      _categoryFilter != _CategoryFilter.all ||
      widget.runId != null;

  List<HttpEventGroup> _applyFilters(List<HttpEventGroup> groups) {
    final query = _searchQuery.trim().toLowerCase();
    final runId = widget.runId;
    return groups.where((g) {
      if (runId != null && !groupMatchesRun(g, runId)) return false;
      if (!_statusMatches(g)) return false;
      if (!_categoryMatches(g)) return false;
      if (query.isNotEmpty &&
          !g.methodLabel.toLowerCase().contains(query) &&
          !g.pathWithQuery.toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }).toList();
  }

  bool _statusMatches(HttpEventGroup g) {
    switch (_statusFilter) {
      case _StatusFilter.all:
        return true;
      case _StatusFilter.success:
        return g.status == HttpEventStatus.success ||
            g.status == HttpEventStatus.streamComplete;
      case _StatusFilter.errors:
        return g.status == HttpEventStatus.networkError ||
            g.status == HttpEventStatus.serverError ||
            g.status == HttpEventStatus.clientError ||
            g.status == HttpEventStatus.streamError;
    }
  }

  bool _categoryMatches(HttpEventGroup g) {
    switch (_categoryFilter) {
      case _CategoryFilter.all:
        return true;
      case _CategoryFilter.llm:
        return categoryOf(g) == HttpCategory.llm;
      case _CategoryFilter.auth:
        return categoryOf(g) == HttpCategory.auth;
      case _CategoryFilter.system:
        return categoryOf(g) == HttpCategory.system;
    }
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _statusFilter = _StatusFilter.all;
      _categoryFilter = _CategoryFilter.all;
    });
    widget.onRunFilterCleared();
  }

  @override
  Widget build(BuildContext context) {
    final allGroups =
        groupHttpEvents(widget.inspector.events).reversed.toList();
    final groups = _applyFilters(allGroups);

    return Column(
      children: [
        ConcurrencySummaryPanel(events: widget.inspector.concurrencyEvents),
        if (allGroups.isNotEmpty)
          _buildToolbar(context, allGroups.length, groups.length),
        Expanded(
          child: allGroups.isEmpty
              ? _buildEmptyState(context)
              : groups.isEmpty
                  ? _buildNoMatchState(context)
                  : _buildList(context, groups),
        ),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context, int total, int visible) {
    final theme = Theme.of(context);
    final runId = widget.runId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SoliplexSpacing.s4,
        SoliplexSpacing.s4,
        SoliplexSpacing.s4,
        SoliplexSpacing.s2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _filterActive
                ? 'Requests ($visible / $total)'
                : 'Requests ($total)',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: SoliplexSpacing.s2),
          SoliplexInput(
            controller: _searchController,
            hintText: 'Filter by method or path…',
            leadingIcon: const Icon(Icons.search),
            trailingIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear search',
                    onPressed: () => setState(() {
                      _searchController.clear();
                      _searchQuery = '';
                    }),
                  )
                : null,
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          const SizedBox(height: SoliplexSpacing.s2),
          Wrap(
            spacing: SoliplexSpacing.s4,
            runSpacing: SoliplexSpacing.s2,
            children: [
              SegmentedButton<_StatusFilter>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: _StatusFilter.all, label: Text('All')),
                  ButtonSegment(
                      value: _StatusFilter.success, label: Text('Success')),
                  ButtonSegment(
                      value: _StatusFilter.errors, label: Text('Errors')),
                ],
                selected: {_statusFilter},
                onSelectionChanged: (selection) =>
                    setState(() => _statusFilter = selection.first),
              ),
              SegmentedButton<_CategoryFilter>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: _CategoryFilter.all, label: Text('All')),
                  ButtonSegment(value: _CategoryFilter.llm, label: Text('LLM')),
                  ButtonSegment(
                      value: _CategoryFilter.auth, label: Text('Auth')),
                  ButtonSegment(
                      value: _CategoryFilter.system, label: Text('System')),
                ],
                selected: {_categoryFilter},
                onSelectionChanged: (selection) =>
                    setState(() => _categoryFilter = selection.first),
              ),
            ],
          ),
          if (runId != null) ...[
            const SizedBox(height: SoliplexSpacing.s2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tag, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: SoliplexSpacing.s1),
                Text(
                  'Run · ${_shortRun(runId)}',
                  style: theme.textTheme.labelMedium,
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  tooltip: 'Clear run filter',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onRunFilterCleared,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, List<HttpEventGroup> groups) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tabular = constraints.maxWidth >= SoliplexBreakpoints.tablet;
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s2),
          itemCount: groups.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) => HttpExchangeTile(
            key: ValueKey(groups[index].requestId),
            group: groups[index],
            tabular: tabular,
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.http,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: SoliplexSpacing.s4),
          Text(
            'No HTTP requests yet',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: SoliplexSpacing.s2),
          Text(
            'Requests will appear here as you use the app',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoMatchState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.filter_alt_off_outlined,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: SoliplexSpacing.s4),
          Text(
            'No requests match these filters',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: SoliplexSpacing.s2),
          SoliplexButton.text(
            onPressed: _clearFilters,
            child: const Text('Clear filters'),
          ),
        ],
      ),
    );
  }

  static String _shortRun(String runId) =>
      runId.length <= 10 ? runId : '${runId.substring(0, 8)}…';
}
