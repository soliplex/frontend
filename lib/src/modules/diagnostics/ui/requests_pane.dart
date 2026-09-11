import 'package:flutter/material.dart';

import 'package:soliplex_design/soliplex_design.dart';

import '../models/http_category.dart';
import '../models/http_event_group.dart';
import '../models/http_event_grouper.dart';
import '../models/run_event_filter.dart';
import '../network_inspector.dart';
import 'concurrency_summary_panel.dart';
import 'http_exchange_tile.dart';
import 'pane_layout.dart';

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
/// reset when the pane is swapped out, which the run filter and the filters'
/// expanded state deliberately do not — see [runId] and [filtersExpanded].
///
/// Reads [inspector] in `build` without listening to it: the screen wraps this
/// pane in a `ListenableBuilder`, so a new instance arrives on every captured
/// event. Mounting it anywhere without that wrapper would leave it stale.
class RequestsPane extends StatefulWidget {
  const RequestsPane({
    required this.inspector,
    required this.onRunFilterCleared,
    required this.viewSwitcher,
    required this.filtersExpanded,
    required this.onFiltersExpandedToggled,
    this.runId,
    super.key,
  });

  final NetworkInspector inspector;

  /// The Requests/Logs control, built by the screen and laid out with this
  /// pane's own controls.
  final Widget viewSwitcher;

  /// Whether the search field and the filter toggles are on screen. Collapsing
  /// them hands the space to the list; the heading above them stays either
  /// way, so a filtered list never looks like the whole capture.
  final bool filtersExpanded;

  /// Called by the heading's collapse control. The state itself belongs to the
  /// screen, for the same reason [runId] does.
  final VoidCallback onFiltersExpandedToggled;

  /// When set (via the per-message deep link), the list is scoped to this agent
  /// run and shows a removable run scope. Owned by the screen, because
  /// dismissing it has to survive a switch to the Logs pane and back.
  final String? runId;

  /// Called when the user dismisses the run scope. Required even though
  /// [runId] is nullable: a scoped list with no way to unscope it is a dead
  /// end, with a "Clear filters" button that cannot clear.
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
        Expanded(
          child: PaneLayout(
            controls: _buildControls(context, allGroups.length, groups.length),
            list: _buildBody(context, allGroups, groups),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<HttpEventGroup> allGroups,
    List<HttpEventGroup> groups,
  ) {
    if (allGroups.isEmpty) return _buildEmptyState(context);
    if (groups.isEmpty) return _buildNoMatchState(context);
    return _buildList(groups);
  }

  Widget _buildControls(BuildContext context, int total, int visible) {
    // A filter outlives the capture it was narrowing: clearing the list
    // leaves the query and the buckets set, and hiding them here would apply
    // them to everything that arrives next with nothing on screen saying so.
    final anythingToFilter = total > 0 || _filterActive;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The count and the run scope say rows are being withheld, which a
        // reader with the filters hidden cannot otherwise see, so they sit
        // outside the collapsible block. The scope shows whenever it is set,
        // because a run id makes [_filterActive] true.
        if (anythingToFilter) ...[
          _buildHeading(context, total, visible),
          const SizedBox(height: SoliplexSpacing.s1),
          if (widget.runId case final runId?) ...[
            _buildRunScope(context, runId),
            const SizedBox(height: SoliplexSpacing.s1),
          ],
        ],
        widget.viewSwitcher,
        if (anythingToFilter && widget.filtersExpanded) ..._buildFilters(),
      ],
    );
  }

  Widget _buildHeading(BuildContext context, int total, int visible) {
    return Row(
      // Flush right against the full-width switcher below, so the heading and
      // the control read as the two ends of one row.
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Half the row each, so neither can push the other off the edge.
        // The count ellipsizes rather than wrapping into its half: at a large
        // Dynamic Type setting 'Requests' alone is wider than the half, and
        // a lone token cannot wrap — it would be clipped mid-glyph.
        Flexible(
          child: Text(
            _filterActive
                ? 'Requests ($visible / $total)'
                : 'Requests ($total)',
            style: Theme.of(context).textTheme.titleMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Named and pointed, not a glyph: an icon alone says neither what
        // it acts on nor which state it is in.
        Flexible(
          child: SoliplexButton.text(
            icon: Icon(
                widget.filtersExpanded ? Icons.expand_less : Icons.expand_more),
            iconAlignment: IconAlignment.end,
            onPressed: widget.onFiltersExpandedToggled,
            child: Text(
              widget.filtersExpanded ? 'Hide filters' : 'Show filters',
            ),
          ),
        ),
      ],
    );
  }

  /// Hand-rolled rather than a [SoliplexChip]: that one's delete button
  /// takes Material's generic tooltip, and this affordance has to name what
  /// it drops.
  Widget _buildRunScope(BuildContext context, String runId) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.tag, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: SoliplexSpacing.s1),
        // Flexible, or a non-flex child of a Row lays out against an
        // unbounded width and runs off the edge at a large Dynamic Type
        // setting. The id is already shortened, so the ellipsis is a floor
        // rather than the usual outcome.
        Flexible(
          child: Text(
            'Run · ${_shortRun(runId)}',
            style: theme.textTheme.labelMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 16),
          tooltip: 'Clear run filter',
          visualDensity: VisualDensity.compact,
          onPressed: widget.onRunFilterCleared,
        ),
      ],
    );
  }

  List<Widget> _buildFilters() => [
        const SizedBox(height: SoliplexSpacing.s1),
        _filterToggle<_StatusFilter>(
          segments: const [
            ButtonSegment(value: _StatusFilter.all, label: Text('All')),
            ButtonSegment(value: _StatusFilter.success, label: Text('Success')),
            ButtonSegment(value: _StatusFilter.errors, label: Text('Errors')),
          ],
          selected: _statusFilter,
          onChanged: (value) => setState(() => _statusFilter = value),
        ),
        const SizedBox(height: SoliplexSpacing.s1),
        _filterToggle<_CategoryFilter>(
          segments: const [
            ButtonSegment(value: _CategoryFilter.all, label: Text('All')),
            ButtonSegment(value: _CategoryFilter.llm, label: Text('LLM')),
            ButtonSegment(value: _CategoryFilter.auth, label: Text('Auth')),
            ButtonSegment(value: _CategoryFilter.system, label: Text('System')),
          ],
          selected: _categoryFilter,
          onChanged: (value) => setState(() => _categoryFilter = value),
        ),
        const SizedBox(height: SoliplexSpacing.s1),
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
      ];

  /// One shape for every bucket filter: full width, so they share both edges
  /// with each other and with the switcher above them.
  Widget _filterToggle<T>({
    required List<ButtonSegment<T>> segments,
    required T selected,
    required ValueChanged<T> onChanged,
  }) {
    return SegmentedButton<T>(
      showSelectedIcon: false,
      expandedInsets: EdgeInsets.zero,
      segments: segments,
      selected: {selected},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }

  Widget _buildList(List<HttpEventGroup> groups) {
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
    return _buildPlaceholder(
      context,
      icon: Icons.http,
      title: 'No HTTP requests yet',
      // A filter survives a clear, so the unfiltered promise would be
      // wrong: whatever arrives next is still filtered out of this list.
      detail: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _filterActive
                ? 'Only requests matching your filters will appear here'
                : 'Requests will appear here as you use the app',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          // The state that says rows are withheld is the natural place to
          // stop withholding them, which its milder sibling already does.
          if (_filterActive) ...[
            const SizedBox(height: SoliplexSpacing.s2),
            _clearFiltersButton(),
          ],
        ],
      ),
    );
  }

  Widget _buildNoMatchState(BuildContext context) => _buildPlaceholder(
        context,
        icon: Icons.filter_alt_off_outlined,
        title: 'No requests match these filters',
        detail: _clearFiltersButton(),
      );

  /// Names the run scope when there is one: it goes with the filters, and it
  /// came from a deep link nothing on this screen can put back.
  Widget _clearFiltersButton() => SoliplexButton.text(
        onPressed: _clearFilters,
        child: Text(
          widget.runId == null ? 'Clear filters' : 'Clear filters and run',
        ),
      );

  /// Taller than the floor [PaneLayout] leaves the list, so it scrolls
  /// rather than overflows.
  Widget _buildPlaceholder(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Widget detail,
  }) {
    final theme = Theme.of(context);
    return Center(
      // Squeezed to the list's floor this shows its icon and nothing else,
      // so it says there is more below the way the controls above it do.
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 64,
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: SoliplexSpacing.s4),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: SoliplexSpacing.s2),
              detail,
            ],
          ),
        ),
      ),
    );
  }

  static String _shortRun(String runId) =>
      runId.length <= 10 ? runId : '${runId.substring(0, 8)}…';
}
