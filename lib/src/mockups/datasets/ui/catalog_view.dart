import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../classification_levels.dart';
import '../model.dart';
import '../store.dart';
import 'common.dart';

/// Picking datasets for a thread rather than browsing: each card gets a
/// checkbox, and the room's ceiling decides what can be ticked.
class CatalogPick {
  const CatalogPick({
    required this.ceiling,
    required this.inUse,
    required this.chosen,
    required this.onToggle,
    required this.withinCeiling,
  });

  final String ceiling;

  /// Already in the thread: shown ticked and fixed.
  final Set<String> inUse;
  final Set<String> chosen;
  final ValueChanged<String> onToggle;

  /// Hide what is above the ceiling rather than show it locked.
  final bool withinCeiling;
}

/// The dataset catalog: search, facets, and the results. Built for hundreds
/// of entries — a list to search and narrow, not one to scroll.
///
/// Facets sit in a column beside the results when there is room, and in a
/// bottom sheet behind a "Filters" button when there is not.
class CatalogView extends StatefulWidget {
  const CatalogView({super.key, this.pick, this.onOpen, this.header});

  final CatalogPick? pick;

  /// Opens a dataset's page; null in the picker.
  final ValueChanged<Dataset>? onOpen;

  /// Above the search row: the picker's ceiling toggle.
  final Widget? header;

  @override
  State<CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends State<CatalogView> {
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search =
        TextEditingController(text: DatasetsScope.read(context).query.text);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = DatasetsScope.of(context);
    final pick = widget.pick;
    final results = store.catalog(
      ceiling: pick?.ceiling,
      withinCeiling: pick?.withinCeiling ?? false,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= SoliplexBreakpoints.desktop;
        final list = _Results(
          results: results,
          pick: pick,
          onOpen: widget.onOpen,
          controls: _Controls(
            search: _search,
            count: results.length,
            showFiltersButton: !wide,
          ),
          header: widget.header,
        );
        if (!wide) return list;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 240, child: FacetPanel()),
            const VerticalDivider(width: 1),
            Expanded(child: list),
          ],
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.search,
    required this.count,
    required this.showFiltersButton,
  });

  final TextEditingController search;
  final int count;
  final bool showFiltersButton;

  @override
  Widget build(BuildContext context) {
    final store = DatasetsScope.of(context);
    final theme = Theme.of(context);
    final query = store.query;
    final active = <Widget>[
      for (final facet in Facet.values)
        for (final value in query.selected[facet]!)
          SoliplexChip(
            label: Text('${facet.label}: ${store.facetLabel(facet, value)}'),
            onDeleted: () => store.setFacet(facet, value, selected: false),
          ),
      if (query.searchableOnly)
        SoliplexChip(
          label: const Text('Searchable only'),
          onDeleted: () => store.updateQuery((q) => q.searchableOnly = false),
        ),
      if (query.showDeprecated)
        SoliplexChip(
          label: const Text('Showing deprecated'),
          onDeleted: () => store.updateQuery((q) => q.showDeprecated = false),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SoliplexInput(
                controller: search,
                hintText: 'Search datasets, tags, systems…',
                leadingIcon: const Icon(Icons.search),
                onChanged: (v) => store.updateQuery((q) => q.text = v),
              ),
            ),
            if (showFiltersButton) ...[
              const SizedBox(width: SoliplexSpacing.s2),
              SoliplexButton.outlined(
                onPressed: () => showFacetSheet(context),
                icon: const Icon(Icons.filter_list),
                child: Text(
                  query.activeCount == 0
                      ? 'Filters'
                      : 'Filters (${query.activeCount})',
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: SoliplexSpacing.s2),
        Row(
          children: [
            Expanded(
              child: Text(
                '$count datasets',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            SoliplexDropdown<CatalogSort>(
              initialValue: query.sort,
              width: 240,
              entries: [
                for (final s in CatalogSort.values)
                  SoliplexDropdownEntry(value: s, label: s.label),
              ],
              onSelected: (s) {
                if (s != null) store.updateQuery((q) => q.sort = s);
              },
            ),
          ],
        ),
        if (active.isNotEmpty) ...[
          const SizedBox(height: SoliplexSpacing.s2),
          Wrap(
            spacing: SoliplexSpacing.s2,
            runSpacing: SoliplexSpacing.s2,
            children: [
              ...active,
              SoliplexButton.text(
                isCompact: true,
                onPressed: () => store.updateQuery((q) => q.clear()),
                child: const Text('Clear all'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.results,
    required this.pick,
    required this.onOpen,
    required this.controls,
    required this.header,
  });

  final List<Dataset> results;
  final CatalogPick? pick;
  final ValueChanged<Dataset>? onOpen;
  final Widget controls;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final leading = [if (header != null) header!, controls];
    return ListView.builder(
      padding: const EdgeInsets.all(SoliplexSpacing.s4),
      itemCount: leading.length + (results.isEmpty ? 1 : results.length),
      itemBuilder: (context, i) {
        if (i < leading.length) {
          return Padding(
            padding: const EdgeInsets.only(bottom: SoliplexSpacing.s3),
            child: leading[i],
          );
        }
        if (results.isEmpty) return const _NoResults();
        final d = results[i - leading.length];
        return Padding(
          padding: const EdgeInsets.only(bottom: SoliplexSpacing.s2),
          child: DatasetCard(
            dataset: d,
            pick: pick,
            onOpen: onOpen == null ? null : () => onOpen!(d),
          ),
        );
      },
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(SoliplexSpacing.s6),
      child: Text(
        'No datasets match. Datasets you are not cleared for, or not shared '
        'with, are never listed.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// One dataset in the catalog.
class DatasetCard extends StatelessWidget {
  const DatasetCard({required this.dataset, super.key, this.pick, this.onOpen});

  final Dataset dataset;
  final CatalogPick? pick;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final store = DatasetsScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final d = dataset;
    final pick = this.pick;
    final locked = pick != null && !isWithin(d.level, pick.ceiling);
    final inUse = pick?.inUse.contains(d.id) ?? false;
    final chosen = inUse || (pick?.chosen.contains(d.id) ?? false);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    VoidCallback? onTap = onOpen;
    if (pick != null) {
      onTap = locked || inUse ? null : () => pick.onToggle(d.id);
    }

    final card = Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(SoliplexSpacing.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (pick != null)
                    Checkbox(
                      value: chosen,
                      onChanged: onTap == null ? null : (_) => onTap!(),
                    ),
                  LevelBadge(d.level),
                  const SizedBox(width: SoliplexSpacing.s2),
                  Expanded(child: DatasetLabel(d)),
                  if (locked)
                    Icon(Icons.lock, size: 18, color: scheme.outline)
                  else
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: store.isPinned(d.id)
                          ? 'Unpin'
                          : 'Pin to your datasets',
                      icon: Icon(
                        store.isPinned(d.id)
                            ? Icons.push_pin
                            : Icons.push_pin_outlined,
                        size: 18,
                      ),
                      onPressed: () => store.togglePin(d.id),
                    ),
                ],
              ),
              const SizedBox(height: SoliplexSpacing.s1),
              Text(d.title, style: theme.textTheme.titleSmall),
              if (d.description.isNotEmpty)
                Text(
                  d.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
              const SizedBox(height: SoliplexSpacing.s2),
              Wrap(
                spacing: SoliplexSpacing.s2,
                runSpacing: SoliplexSpacing.s1,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DatasetStatusBadge(d, showPrivate: store.isOwner(d)),
                  for (final tag in d.tags.all.take(3))
                    SoliplexBadge(label: Text(tag)),
                ],
              ),
              const SizedBox(height: SoliplexSpacing.s2),
              Text(
                '${d.files.length} files · ${store.ownerName(d)} · updated '
                '${formatAgo(d.updatedAt)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (locked) ...[
                const SizedBox(height: SoliplexSpacing.s1),
                Text(
                  "Above this room's level (${levelLabel(d.level)} > "
                  '${levelLabel(pick.ceiling)})',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ] else if (inUse) ...[
                const SizedBox(height: SoliplexSpacing.s1),
                Text('Already in this thread', style: muted),
              ],
            ],
          ),
        ),
      ),
    );
    return locked ? Opacity(opacity: 0.55, child: card) : card;
  }
}

/// The facet column: counts per value among what the search matches.
class FacetPanel extends StatelessWidget {
  const FacetPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final store = DatasetsScope.of(context);
    final query = store.query;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s3),
      children: [
        SwitchListTile(
          dense: true,
          title: const Text('Searchable only'),
          value: query.searchableOnly,
          onChanged: (v) => store.updateQuery((q) => q.searchableOnly = v),
        ),
        SwitchListTile(
          dense: true,
          title: const Text('Show deprecated'),
          value: query.showDeprecated,
          onChanged: (v) => store.updateQuery((q) => q.showDeprecated = v),
        ),
        const Divider(),
        for (final facet in Facet.values) _FacetGroup(facet: facet),
      ],
    );
  }
}

class _FacetGroup extends StatefulWidget {
  const _FacetGroup({required this.facet});

  final Facet facet;

  @override
  State<_FacetGroup> createState() => _FacetGroupState();
}

class _FacetGroupState extends State<_FacetGroup> {
  static const _shown = 6;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final store = DatasetsScope.of(context);
    final theme = Theme.of(context);
    final facet = widget.facet;
    final counts = store.facetCounts(facet);
    if (counts.isEmpty) return const SizedBox.shrink();
    final selected = store.query.selected[facet]!;
    final visible = _all ? counts : counts.take(_shown);
    return Padding(
      padding: const EdgeInsets.only(bottom: SoliplexSpacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SoliplexSpacing.s4,
              vertical: SoliplexSpacing.s1,
            ),
            child: Text(facet.label, style: theme.textTheme.titleSmall),
          ),
          for (final (value, count) in visible)
            CheckboxListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              controlAffinity: ListTileControlAffinity.leading,
              value: selected.contains(value),
              onChanged: (v) =>
                  store.setFacet(facet, value, selected: v ?? false),
              title: facet == Facet.level
                  // Shrinks a long marking to fit the column rather than
                  // breaking it mid-word.
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: LevelBadge(value),
                    )
                  : Text(
                      store.facetLabel(facet, value),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              secondary: Text(
                '$count',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (counts.length > _shown)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s2),
              child: SoliplexButton.text(
                isCompact: true,
                onPressed: () => setState(() => _all = !_all),
                child: Text(_all ? 'Show fewer' : 'Show all ${counts.length}'),
              ),
            ),
        ],
      ),
    );
  }
}

/// The facets in a sheet, for when there is no room for the column.
Future<void> showFacetSheet(BuildContext context) {
  final store = DatasetsScope.read(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => DatasetsScope(
      store: store,
      child: const FractionallySizedBox(
        heightFactor: 0.8,
        child: FacetPanel(),
      ),
    ),
  );
}

/// Picks datasets to add to a thread: the catalog with checkboxes, the room's
/// ceiling enforced, in a dialog when wide and full screen when not. Returns
/// the ids picked, or null when dismissed.
Future<List<String>?> showDatasetPicker(
  BuildContext context, {
  required String ceiling,
  required Set<String> inUse,
}) {
  final store = DatasetsScope.read(context);
  final wide = MediaQuery.sizeOf(context).width >= SoliplexBreakpoints.desktop;
  final picker = DatasetsScope(
    store: store,
    child: _Picker(ceiling: ceiling, inUse: inUse),
  );
  if (wide) {
    return showDialog<List<String>>(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(width: 1000, height: 720, child: picker),
      ),
    );
  }
  return Navigator.of(context).push<List<String>>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => picker),
  );
}

class _Picker extends StatefulWidget {
  const _Picker({required this.ceiling, required this.inUse});

  final String ceiling;
  final Set<String> inUse;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  final _chosen = <String>{};
  bool _withinCeiling = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add datasets'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: CatalogView(
        pick: CatalogPick(
          ceiling: widget.ceiling,
          inUse: widget.inUse,
          chosen: _chosen,
          withinCeiling: _withinCeiling,
          onToggle: (id) => setState(
            () => _chosen.contains(id) ? _chosen.remove(id) : _chosen.add(id),
          ),
        ),
        header: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: SoliplexSpacing.s4,
          runSpacing: SoliplexSpacing.s2,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("This room's level", style: theme.textTheme.labelMedium),
                const SizedBox(width: SoliplexSpacing.s2),
                LevelBadge(widget.ceiling),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Within room level', style: theme.textTheme.labelMedium),
                Switch(
                  value: _withinCeiling,
                  onChanged: (v) => setState(() => _withinCeiling = v),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SoliplexSpacing.s3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SoliplexButton.text(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: SoliplexSpacing.s2),
              SoliplexButton.filled(
                onPressed: _chosen.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(_chosen.toList()),
                child: Text(
                  _chosen.isEmpty
                      ? 'Add datasets'
                      : 'Add ${_chosen.length} '
                          '${_chosen.length == 1 ? 'dataset' : 'datasets'}',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
