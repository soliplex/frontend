import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show BaseEvent, ThreadKey;

import '../../auth/auth_providers.dart';
import '../bus_filter.dart';
import '../bus_inspector.dart';
import '../models/json_tree_model.dart';
import '../snapshot_diff.dart';
import 'json_tree_view.dart';

const double _wideBreakpoint = 720;
const double _sidebarWidth = 260;

class BusInspectorScreen extends ConsumerStatefulWidget {
  const BusInspectorScreen({required this.inspector, super.key});

  final BusInspector inspector;

  @override
  ConsumerState<BusInspectorScreen> createState() => _BusInspectorScreenState();
}

class _BusInspectorScreenState extends ConsumerState<BusInspectorScreen> {
  /// `null` means "All events"; otherwise filter to a single thread.
  ThreadKey? _selectedThread;

  final TextEditingController _filterController = TextEditingController();

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  void _openThread(ThreadKey key) {
    final entry = ref.read(serverManagerProvider).servers.value[key.serverId];
    if (entry == null) return;
    context.go('/room/${entry.alias}/${key.roomId}/thread/${key.threadId}');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.inspector,
      builder: (context, _) {
        final allRows = _buildUnifiedRows(
          widget.inspector.events,
          widget.inspector.eventRecords,
        );
        final threadStats = _summariseThreads(allRows);
        final filter = parseBusFilter(_filterController.text);
        final scopedRows = _selectedThread == null
            ? allRows
            : allRows.where((r) => r.threadKey == _selectedThread).toList();
        final visibleRows = filter.isEmpty
            ? scopedRows
            : scopedRows.where((r) => r.matchesFilter(filter)).toList();
        final reversed = visibleRows.reversed.toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Bus Inspector'),
            actions: [
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: allRows.isEmpty
                    ? null
                    : () {
                        widget.inspector.clear();
                      },
                tooltip: 'Clear all events',
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= _wideBreakpoint;
              if (isWide) {
                return Row(
                  children: [
                    SizedBox(
                      width: _sidebarWidth,
                      child: _ThreadSidebar(
                        stats: threadStats,
                        totalEventCount: allRows.length,
                        selected: _selectedThread,
                        onSelect: (key) =>
                            setState(() => _selectedThread = key),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _EventsPane(
                        rows: reversed,
                        filterController: _filterController,
                        events: widget.inspector.events,
                        eventRecords: widget.inspector.eventRecords,
                        onFilterChanged: () => setState(() {}),
                        onOpenThread: _openThread,
                      ),
                    ),
                  ],
                );
              }
              // Narrow: sidebar OR events. Sidebar shows when no
              // thread is selected; selecting one swaps to events.
              if (_selectedThread == null && _filterController.text.isEmpty) {
                return _ThreadSidebar(
                  stats: threadStats,
                  totalEventCount: allRows.length,
                  selected: null,
                  onSelect: (key) => setState(() => _selectedThread = key),
                );
              }
              return _EventsPane(
                rows: reversed,
                filterController: _filterController,
                events: widget.inspector.events,
                eventRecords: widget.inspector.eventRecords,
                onFilterChanged: () => setState(() {}),
                onOpenThread: _openThread,
                onBack: () => setState(() {
                  _selectedThread = null;
                  _filterController.clear();
                }),
              );
            },
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Sidebar
// ---------------------------------------------------------------------------

class _ThreadStat {
  _ThreadStat({
    required this.key,
    required this.eventCount,
    required this.lastEventAt,
  });

  final ThreadKey key;
  final int eventCount;
  final DateTime lastEventAt;
}

List<_ThreadStat> _summariseThreads(List<_Row> rows) {
  final stats = <ThreadKey, _ThreadStat>{};
  for (final row in rows) {
    final existing = stats[row.threadKey];
    if (existing == null) {
      stats[row.threadKey] = _ThreadStat(
        key: row.threadKey,
        eventCount: 1,
        lastEventAt: row.timestamp,
      );
    } else {
      stats[row.threadKey] = _ThreadStat(
        key: existing.key,
        eventCount: existing.eventCount + 1,
        lastEventAt: row.timestamp.isAfter(existing.lastEventAt)
            ? row.timestamp
            : existing.lastEventAt,
      );
    }
  }
  final list = stats.values.toList()
    ..sort((a, b) => b.lastEventAt.compareTo(a.lastEventAt));
  return list;
}

class _ThreadSidebar extends StatelessWidget {
  const _ThreadSidebar({
    required this.stats,
    required this.totalEventCount,
    required this.selected,
    required this.onSelect,
  });

  final List<_ThreadStat> stats;
  final int totalEventCount;
  final ThreadKey? selected;
  final ValueChanged<ThreadKey?> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: ListView(
        children: [
          ListTile(
            selected: selected == null,
            dense: true,
            leading: const Icon(Icons.all_inbox_outlined, size: 20),
            title: const Text('All events'),
            trailing: Text(
              '$totalEventCount',
              style: theme.textTheme.labelSmall,
            ),
            onTap: () => onSelect(null),
          ),
          if (stats.isNotEmpty) const Divider(height: 1),
          for (final s in stats)
            ListTile(
              selected: selected == s.key,
              dense: true,
              leading: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _threadColor(s.key),
                  shape: BoxShape.circle,
                ),
              ),
              title: Text(
                s.key.roomId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              subtitle: Text(
                '${_threadShort(s.key)} · last ${_formatTime(s.lastEventAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: Text(
                '${s.eventCount}',
                style: theme.textTheme.labelSmall,
              ),
              onTap: () => onSelect(s.key),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Events pane (filter + list + inline detail)
// ---------------------------------------------------------------------------

class _EventsPane extends StatefulWidget {
  const _EventsPane({
    required this.rows,
    required this.filterController,
    required this.events,
    required this.eventRecords,
    required this.onFilterChanged,
    required this.onOpenThread,
    this.onBack,
  });

  final List<_Row> rows;
  final TextEditingController filterController;
  final List<BusEvent> events;
  final List<EventRecord> eventRecords;
  final VoidCallback onFilterChanged;
  final void Function(ThreadKey) onOpenThread;
  final VoidCallback? onBack;

  @override
  State<_EventsPane> createState() => _EventsPaneState();
}

class _EventsPaneState extends State<_EventsPane> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    return Column(
      children: [
        _FilterBar(
          controller: widget.filterController,
          events: widget.events,
          eventRecords: widget.eventRecords,
          onChanged: () {
            widget.onFilterChanged();
            setState(() => _selectedIndex = null);
          },
          onBack: widget.onBack,
        ),
        const Divider(height: 1),
        Expanded(
          child: rows.isEmpty
              ? _buildEmptyState(context)
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 600;
                    if (isWide) {
                      return _buildMasterDetail(context, rows);
                    }
                    return _buildList(context, rows, sheetMode: true);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bubble_chart_outlined,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              widget.filterController.text.isEmpty
                  ? 'No bus events yet'
                  : 'No events match this filter',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    List<_Row> rows, {
    required bool sheetMode,
  }) {
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) => _RowTile(
        row: rows[index],
        selected: _selectedIndex == index,
        onTap: sheetMode
            ? () => _showDetailSheet(context, rows[index])
            : () => setState(() => _selectedIndex = index),
        onOpenThread: () => widget.onOpenThread(rows[index].threadKey),
      ),
    );
  }

  Widget _buildMasterDetail(BuildContext context, List<_Row> rows) {
    final selected = _selectedIndex != null && _selectedIndex! < rows.length
        ? rows[_selectedIndex!]
        : null;
    return Row(
      children: [
        SizedBox(
          width: 360,
          child: _buildList(context, rows, sheetMode: false),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: selected == null
              ? _buildDetailPlaceholder(context)
              : SingleChildScrollView(
                  child: _RowDetail(
                    row: selected,
                    onOpenThread: () => widget.onOpenThread(selected.threadKey),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildDetailPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        'Select an event to inspect its diff.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Future<void> _showDetailSheet(BuildContext context, _Row row) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          child: _RowDetail(
            row: row,
            onOpenThread: () => widget.onOpenThread(row.threadKey),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter bar with inline autocomplete chips
// ---------------------------------------------------------------------------

class _FilterBar extends StatefulWidget {
  const _FilterBar({
    required this.controller,
    required this.events,
    required this.eventRecords,
    required this.onChanged,
    this.onBack,
  });

  final TextEditingController controller;
  final List<BusEvent> events;
  final List<EventRecord> eventRecords;
  final VoidCallback onChanged;
  final VoidCallback? onBack;

  @override
  State<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<_FilterBar> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focus
      ..removeListener(_onFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _onTextChanged() {
    widget.onChanged();
    setState(() {});
  }

  void _onFocusChanged() => setState(() {});

  void _applySuggestion(String suggestion) {
    final cursor = widget.controller.selection.baseOffset.clamp(
      0,
      widget.controller.text.length,
    );
    final at = currentTokenAt(widget.controller.text, cursor);
    final start = at?.start ?? cursor;
    final end = at?.end ?? cursor;
    final before = widget.controller.text.substring(0, start);
    final after = widget.controller.text.substring(end);
    // Append a trailing space if there isn't one — lets the user type
    // the next filter immediately without manual delimiter.
    final needsSpace = after.isEmpty || !after.startsWith(' ');
    final inserted = needsSpace ? '$suggestion ' : suggestion;
    final replaced = '$before$inserted$after';
    final newCursor = (before + inserted).length;
    widget.controller.value = TextEditingValue(
      text: replaced,
      selection: TextSelection.collapsed(offset: newCursor),
    );
    _focus.requestFocus();
  }

  void _removeToken(int index) {
    final tokens = widget.controller.text.split(RegExp(r'\s+'))
      ..removeWhere((t) => t.isEmpty);
    if (index < 0 || index >= tokens.length) return;
    tokens.removeAt(index);
    widget.controller.text = tokens.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cursor = widget.controller.selection.baseOffset.clamp(
      0,
      widget.controller.text.length,
    );
    final suggestions = _focus.hasFocus
        ? suggestionsFor(
            text: widget.controller.text,
            cursor: cursor,
            events: widget.events,
            records: widget.eventRecords,
          ).take(8).toList()
        : <String>[];

    final activeTokens = widget.controller.text
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();

    return TapRegion(
      groupId: 'bus-filter-bar',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (widget.onBack != null)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: widget.onBack,
                    tooltip: 'Back to threads',
                  ),
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focus,
                    // Default unfocuses the field on any outside tap,
                    // which kills the suggestion chips: the rebuild
                    // triggered by focus loss unmounts the chip before
                    // its `onPressed` can fire. Override with a no-op
                    // so the field keeps focus until the user
                    // explicitly leaves the filter area.
                    onTapOutside: (_) {},
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: widget.controller.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => widget.controller.clear(),
                              tooltip: 'Clear filter',
                            ),
                      hintText:
                          'Filter: kind:bus|event tag:agui.* thread:abc path:/ui',
                      hintStyle: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
            if (activeTokens.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < activeTokens.length; i++)
                    InputChip(
                      label: Text(
                        activeTokens[i],
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontFamily: 'monospace'),
                      ),
                      onDeleted: () => _removeToken(i),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 6),
              SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: suggestions.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, index) {
                    final s = suggestions[index];
                    return ActionChip(
                      label: Text(
                        s,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontFamily: 'monospace'),
                      ),
                      onPressed: () {
                        debugPrint('[BUS-INSPECTOR] chip onPressed: "$s"');
                        _applySuggestion(s);
                      },
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Unified row hierarchy + builder
// ---------------------------------------------------------------------------

sealed class _Row {
  DateTime get timestamp;
  ThreadKey get threadKey;
  String? get tag;

  bool matchesFilter(BusFilter filter);
}

class _BusRow extends _Row {
  _BusRow({required this.event, required this.diff});

  final BusEvent event;
  final SnapshotDiff diff;

  @override
  DateTime get timestamp => event.timestamp;
  @override
  ThreadKey get threadKey => event.threadKey;
  @override
  String? get tag => event.tag;

  @override
  bool matchesFilter(BusFilter filter) => filter.matchesBus(event, diff);
}

class _AguiEventRow extends _Row {
  _AguiEventRow({required this.record});

  final EventRecord record;

  @override
  DateTime get timestamp => record.timestamp;
  @override
  ThreadKey get threadKey => record.threadKey;
  @override
  String? get tag => record.tag;

  @override
  bool matchesFilter(BusFilter filter) => filter.matchesEvent(record);
}

/// Combine bus commits + raw event records into one timestamp-ordered
/// list. Bus rows compute their per-thread diff against the previous
/// commit on the same thread; no-op commits (empty diff) are dropped.
List<_Row> _buildUnifiedRows(
  List<BusEvent> commits,
  List<EventRecord> records,
) {
  final lastSnapshotPerThread = <ThreadKey, Map<String, dynamic>>{};
  final busRows = <_BusRow>[];
  for (final event in commits) {
    final prior = lastSnapshotPerThread[event.threadKey];
    final diff = diffSnapshots(prior, event.snapshot);
    lastSnapshotPerThread[event.threadKey] = event.snapshot;
    if (diff.isEmpty) continue;
    busRows.add(_BusRow(event: event, diff: diff));
  }
  final eventRows = records.map((r) => _AguiEventRow(record: r));
  return [...busRows, ...eventRows]
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
}

// ---------------------------------------------------------------------------
// Tiles + details (dispatch on row kind)
// ---------------------------------------------------------------------------

class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.row,
    required this.selected,
    required this.onTap,
    required this.onOpenThread,
  });

  final _Row row;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onOpenThread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (subtitle, summary) = switch (row) {
      _BusRow(:final diff) => (
          _firstChangedPath(diff) ?? _threadShort(row.threadKey),
          diff.summary,
        ),
      _AguiEventRow(:final record) => (
          _eventSubtitle(record.event),
          'event',
        ),
    };
    return ListTile(
      selected: selected,
      onTap: onTap,
      dense: true,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 4,
            height: 32,
            decoration: BoxDecoration(
              color: _threadColor(row.threadKey),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          _RowKindBadge(row: row),
          const SizedBox(width: 6),
          _TagChip(tag: row.tag),
        ],
      ),
      title: Row(
        children: [
          Text(
            _formatTime(row.timestamp),
            style:
                theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              summary,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontFamily: 'monospace',
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.open_in_new, size: 18),
        tooltip: 'Open thread ${_threadShort(row.threadKey)}',
        onPressed: onOpenThread,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _RowKindBadge extends StatelessWidget {
  const _RowKindBadge({required this.row});

  final _Row row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBus = row is _BusRow;
    final label = isBus ? 'bus' : 'event';
    final color = isBus
        ? theme.colorScheme.tertiaryContainer
        : theme.colorScheme.primaryContainer;
    final fg = isBus
        ? theme.colorScheme.onTertiaryContainer
        : theme.colorScheme.onPrimaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontFamily: 'monospace',
          fontSize: 10,
        ),
      ),
    );
  }
}

class _RowDetail extends StatelessWidget {
  const _RowDetail({required this.row, required this.onOpenThread});

  final _Row row;
  final VoidCallback onOpenThread;

  @override
  Widget build(BuildContext context) => switch (row) {
        _BusRow() =>
          _BusRowDetail(row: row as _BusRow, onOpenThread: onOpenThread),
        _AguiEventRow() => _AguiEventDetail(
            row: row as _AguiEventRow,
            onOpenThread: onOpenThread,
          ),
      };
}

class _BusRowDetail extends StatefulWidget {
  const _BusRowDetail({required this.row, required this.onOpenThread});

  final _BusRow row;
  final VoidCallback onOpenThread;

  @override
  State<_BusRowDetail> createState() => _BusRowDetailState();
}

class _BusRowDetailState extends State<_BusRowDetail> {
  bool _showFullSnapshot = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diff = widget.row.diff;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _TagChip(tag: widget.row.event.tag),
              const SizedBox(width: 12),
              Text(
                _formatTime(widget.row.event.timestamp),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontFamily: 'monospace'),
              ),
              const Spacer(),
              Text(
                diff.summary,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ThreadHeaderRow(
            threadKey: widget.row.event.threadKey,
            onOpenThread: widget.onOpenThread,
          ),
          const Divider(height: 24),
          if (diff.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No changes vs prior commit on this thread.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            _DiffList(diff: diff),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () =>
                setState(() => _showFullSnapshot = !_showFullSnapshot),
            icon: Icon(
              _showFullSnapshot ? Icons.expand_less : Icons.expand_more,
              size: 18,
            ),
            label: Text(_showFullSnapshot
                ? 'Hide full snapshot'
                : 'Show full snapshot'),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              alignment: Alignment.centerLeft,
            ),
          ),
          if (_showFullSnapshot)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: JsonTreeView(
                nodes: buildJsonTree(widget.row.event.snapshot),
              ),
            ),
        ],
      ),
    );
  }
}

class _AguiEventDetail extends StatelessWidget {
  const _AguiEventDetail({required this.row, required this.onOpenThread});

  final _AguiEventRow row;
  final VoidCallback onOpenThread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final event = row.record.event;
    final json = _eventJson(event);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _TagChip(tag: row.record.tag),
              const SizedBox(width: 12),
              Text(
                _formatTime(row.record.timestamp),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontFamily: 'monospace'),
              ),
              const Spacer(),
              Text(
                event.runtimeType.toString(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _ThreadHeaderRow(
            threadKey: row.record.threadKey,
            onOpenThread: onOpenThread,
          ),
          const Divider(height: 24),
          if (json.isEmpty)
            Text(
              '(no payload — event is fields-only)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            JsonTreeView(nodes: buildJsonTree(json)),
        ],
      ),
    );
  }
}

class _ThreadHeaderRow extends StatelessWidget {
  const _ThreadHeaderRow({
    required this.threadKey,
    required this.onOpenThread,
  });

  final ThreadKey threadKey;
  final VoidCallback onOpenThread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: SelectableText(
            'thread: ${_threadFull(threadKey)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
        ),
        TextButton.icon(
          onPressed: onOpenThread,
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('Open thread'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            minimumSize: const Size(0, 32),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}

class _DiffList extends StatelessWidget {
  const _DiffList({required this.diff});

  final SnapshotDiff diff;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in diff.added) _ChangeLine.added(c),
        for (final c in diff.removed) _ChangeLine.removed(c),
        for (final c in diff.replaced) _ChangeLine.replaced(c),
      ],
    );
  }
}

class _ChangeLine extends StatelessWidget {
  const _ChangeLine._({
    required this.path,
    required this.symbol,
    required this.color,
    required this.value,
  });

  factory _ChangeLine.added(AddedChange c) => _ChangeLine._(
        path: c.path,
        symbol: '+',
        color: Colors.green.shade700,
        value: _formatValue(c.value),
      );

  factory _ChangeLine.removed(RemovedChange c) => _ChangeLine._(
        path: c.path,
        symbol: '-',
        color: Colors.red.shade700,
        value: _formatValue(c.value),
      );

  factory _ChangeLine.replaced(ReplacedChange c) => _ChangeLine._(
        path: c.path,
        symbol: '~',
        color: Colors.amber.shade800,
        value: '${_formatValue(c.before)} → ${_formatValue(c.after)}',
      );

  final String path;
  final String symbol;
  final Color color;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SelectableText.rich(
        TextSpan(
          style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          children: [
            TextSpan(
              text: '$symbol ',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
            TextSpan(
              text: path,
              style: TextStyle(color: theme.colorScheme.onSurface),
            ),
            const TextSpan(text: '  '),
            TextSpan(
              text: value,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.tag});

  final String? tag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayTag = tag ?? 'untagged';
    final bg = tag == null
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.secondaryContainer;
    final fg = tag == null
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        displayTag,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fg,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Color _threadColor(ThreadKey key) {
  const palette = <Color>[
    Color(0xFF1976D2),
    Color(0xFF388E3C),
    Color(0xFF7B1FA2),
    Color(0xFFE64A19),
    Color(0xFFC2185B),
    Color(0xFF00796B),
    Color(0xFF5D4037),
    Color(0xFF455A64),
  ];
  return palette[key.threadId.hashCode.abs() % palette.length];
}

String _formatTime(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  final s = t.second.toString().padLeft(2, '0');
  final ms = t.millisecond.toString().padLeft(3, '0');
  return '$h:$m:$s.$ms';
}

String _threadShort(ThreadKey key) {
  final tid = key.threadId;
  return tid.length <= 6 ? tid : tid.substring(tid.length - 6);
}

String _threadFull(ThreadKey key) =>
    '${key.serverId}/${key.roomId}/${key.threadId}';

String? _firstChangedPath(SnapshotDiff diff) {
  if (diff.added.isNotEmpty) return diff.added.first.path;
  if (diff.replaced.isNotEmpty) return diff.replaced.first.path;
  if (diff.removed.isNotEmpty) return diff.removed.first.path;
  return null;
}

/// One-line summary used as the tile subtitle for an AG-UI event row.
/// Picks the most informative field from the event's JSON form
/// (messageId, activityType, etc.); falls back to runtime type.
String _eventSubtitle(BaseEvent event) {
  final json = _eventJson(event);
  // Boring fields the user already sees elsewhere (timestamp + the
  // tag derived from runtime type covers `type`).
  const skip = {'type', 'eventType', 'timestamp', 'rawEvent'};
  for (final entry in json.entries) {
    if (skip.contains(entry.key)) continue;
    final value = entry.value;
    if (value == null) continue;
    final repr = _briefValue(value);
    return '${entry.key}=$repr';
  }
  return event.runtimeType.toString();
}

/// Pulls the event's structured fields via `toJson()`. All ag_ui
/// `BaseEvent` subclasses provide this; it is the authoritative
/// payload representation.
Map<String, dynamic> _eventJson(BaseEvent event) {
  try {
    return event.toJson();
  } on Object {
    // toJson can in principle throw; fall back to an empty map so the
    // detail view still renders the runtime type.
    return const {};
  }
}

String _briefValue(dynamic value) {
  if (value is String) {
    if (value.length > 60) return '"${value.substring(0, 57)}..."';
    return '"$value"';
  }
  if (value is num || value is bool) return value.toString();
  if (value is Map) {
    return '{…} (${value.length} key${value.length == 1 ? '' : 's'})';
  }
  if (value is List) return '[…] (${value.length})';
  return value.toString();
}

String _formatValue(dynamic value) {
  if (value == null) return 'null';
  if (value is String) {
    if (value.length > 60) return '"${value.substring(0, 57)}..."';
    return '"$value"';
  }
  if (value is num || value is bool) return value.toString();
  if (value is Map) {
    return '{…} (${value.length} key${value.length == 1 ? '' : 's'})';
  }
  if (value is List) return '[…] (${value.length})';
  return value.toString();
}
