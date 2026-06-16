import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soliplex_design/soliplex_design.dart';
import '../../../core/routes.dart';
import '../../auth/ui/home_shell.dart';
import '../models/http_event_group.dart';
import '../models/http_event_grouper.dart';
import '../models/run_event_filter.dart';
import '../network_inspector.dart';
import 'concurrency_summary_panel.dart';
import 'http_exchange_tile.dart';

/// Status buckets for the inspector's quick filter. `pending`/`streaming`
/// in-flight exchanges only show under [all].
enum _StatusFilter { all, success, errors }

class NetworkInspectorScreen extends StatefulWidget {
  const NetworkInspectorScreen({
    required this.appName,
    required this.inspector,
    this.logo,
    this.initialRunId,
    super.key,
  });

  final String appName;
  final Widget? logo;
  final NetworkInspector inspector;

  /// When set (via the per-message deep link), the list opens scoped to this
  /// agent run, shown as a removable chip. Null for the plain inspector.
  final String? initialRunId;

  @override
  State<NetworkInspectorScreen> createState() => _NetworkInspectorScreenState();
}

class _NetworkInspectorScreenState extends State<NetworkInspectorScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  _StatusFilter _statusFilter = _StatusFilter.all;
  String? _runId;

  @override
  void initState() {
    super.initState();
    _runId = widget.initialRunId;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _filterActive =>
      _searchQuery.isNotEmpty ||
      _statusFilter != _StatusFilter.all ||
      _runId != null;

  List<HttpEventGroup> _applyFilters(List<HttpEventGroup> groups) {
    final query = _searchQuery.trim().toLowerCase();
    final runId = _runId;
    return groups.where((g) {
      if (runId != null && !groupMatchesRun(g, runId)) return false;
      if (!_statusMatches(g)) return false;
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

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _statusFilter = _StatusFilter.all;
      _runId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.inspector,
      builder: (context, _) {
        final allGroups =
            groupHttpEvents(widget.inspector.events).reversed.toList();
        final groups = _applyFilters(allGroups);

        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                HomeShellHeader(
                  appName: widget.appName,
                  logo: widget.logo,
                  showAbout: false,
                  leading: IconButton(
                    icon: Icon(Icons.adaptive.arrow_back),
                    tooltip: 'Back',
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go(AppRoutes.lobby),
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_outlined),
                      onPressed: widget.inspector.events.isEmpty &&
                              widget.inspector.concurrencyEvents.isEmpty
                          ? null
                          : widget.inspector.clear,
                      tooltip: 'Clear all requests',
                    ),
                  ],
                ),
                ConcurrencySummaryPanel(
                  events: widget.inspector.concurrencyEvents,
                ),
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
            ),
          ),
        );
      },
    );
  }

  Widget _buildToolbar(BuildContext context, int total, int visible) {
    final theme = Theme.of(context);
    final runId = _runId;
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
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<_StatusFilter>(
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
                  onPressed: () => setState(() => _runId = null),
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
