import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../../../core/routes.dart';
import '../../../modules/lobby/ui/room_grid_layout.dart';
import '../model.dart';
import '../store.dart';
import 'catalog_view.dart';
import 'common.dart';

/// The lobby with datasets beside rooms: rooms are presets to start from,
/// datasets the catalog to pick from. The switch is in the URL, so coming
/// back from a dataset lands on the catalog.
class DatasetsLobbyScreen extends StatelessWidget {
  const DatasetsLobbyScreen({
    required this.serverAlias,
    required this.showDatasets,
    super.key,
  });

  final String serverAlias;
  final bool showDatasets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final narrow =
        MediaQuery.sizeOf(context).width < SoliplexBreakpoints.tablet;
    final toggle = SegmentedButton<bool>(
      segments: const [
        ButtonSegment(
          value: false,
          label: Text('Rooms'),
          icon: Icon(Icons.meeting_room_outlined),
        ),
        ButtonSegment(
          value: true,
          label: Text('Datasets'),
          icon: Icon(Icons.dataset_outlined),
        ),
      ],
      selected: {showDatasets},
      showSelectedIcon: false,
      onSelectionChanged: (s) =>
          context.go(s.first ? '/lobby?view=datasets' : AppRoutes.lobby),
    );
    final newDataset = narrow
        ? IconButton.filled(
            tooltip: 'New dataset',
            icon: const Icon(Icons.add),
            onPressed: () => context.go('/datasets/new'),
          )
        : SoliplexButton.filled(
            onPressed: () => context.go('/datasets/new'),
            icon: const Icon(Icons.add),
            child: const Text('New dataset'),
          );
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SoliplexSpacing.s4,
                SoliplexSpacing.s4,
                SoliplexSpacing.s4,
                SoliplexSpacing.s2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Lobby', style: theme.textTheme.headlineMedium),
                  ),
                  if (!narrow) toggle,
                  if (showDatasets) ...[
                    const SizedBox(width: SoliplexSpacing.s3),
                    newDataset,
                  ],
                ],
              ),
            ),
            if (narrow)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SoliplexSpacing.s4,
                  vertical: SoliplexSpacing.s2,
                ),
                child: toggle,
              ),
            const Divider(height: 1),
            Expanded(
              child: showDatasets
                  ? CatalogView(
                      onOpen: (d) => context.go('/datasets/${d.id}'),
                    )
                  : _RoomGrid(serverAlias: serverAlias),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomGrid extends StatelessWidget {
  const _RoomGrid({required this.serverAlias});

  final String serverAlias;

  @override
  Widget build(BuildContext context) {
    final store = DatasetsScope.of(context);
    final presets = store.presets.values.toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        // One column on a phone: a preset card carries more than a room's.
        final columns = constraints.maxWidth < SoliplexBreakpoints.tablet
            ? 1
            : roomGridColumns(constraints.maxWidth);
        return ListView(
          padding: const EdgeInsets.all(SoliplexSpacing.s4),
          children: [
            for (var i = 0; i < presets.length; i += columns)
              Padding(
                padding: const EdgeInsets.only(bottom: SoliplexSpacing.s3),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var j = i; j < i + columns; j++) ...[
                        if (j > i) const SizedBox(width: SoliplexSpacing.s3),
                        Expanded(
                          child: j < presets.length
                              ? RoomPresetCard(
                                  preset: presets[j],
                                  onOpen: () => context.go(
                                    AppRoutes.room(
                                      serverAlias,
                                      presets[j].roomId,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A room as a preset: its level ceiling and the datasets a new thread in it
/// starts with. Read-only — the deployer owns presets.
class RoomPresetCard extends StatelessWidget {
  const RoomPresetCard({required this.preset, required this.onOpen, super.key});

  final RoomPreset preset;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final store = DatasetsScope.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final defaults =
        [for (final id in preset.defaultDatasetIds) store.byId(id)].nonNulls;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(SoliplexSpacing.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(preset.name, style: theme.textTheme.titleMedium),
              const SizedBox(height: SoliplexSpacing.s1),
              Text(
                preset.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: muted,
              ),
              const SizedBox(height: SoliplexSpacing.s3),
              Wrap(
                spacing: SoliplexSpacing.s2,
                runSpacing: SoliplexSpacing.s1,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('Room level', style: theme.textTheme.labelSmall),
                  LevelBadge(preset.ceiling),
                ],
              ),
              const SizedBox(height: SoliplexSpacing.s3),
              Text('Default datasets', style: theme.textTheme.labelSmall),
              const SizedBox(height: SoliplexSpacing.s1),
              for (final d in defaults.take(2)) DatasetLabel(d),
              if (defaults.length > 2)
                Text('+${defaults.length - 2} more', style: muted),
              const Spacer(),
              const SizedBox(height: SoliplexSpacing.s3),
              Row(
                children: [
                  Icon(
                    Icons.extension_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: SoliplexSpacing.s1),
                  Expanded(
                    child: Text(
                      '${preset.skills.length} skills',
                      style: muted,
                    ),
                  ),
                  Tooltip(
                    message: 'Set by the deployer. Change datasets per thread '
                        'before the first message.',
                    child: Icon(
                      Icons.admin_panel_settings_outlined,
                      size: 16,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
