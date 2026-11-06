import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'package:soliplex_client/soliplex_client.dart' show ThreadInfo;

import '../../../core/routes.dart';
import '../../../core/ui/confirm_dialog.dart';
import '../../../modules/auth/server_entry.dart';
import '../../../modules/lobby/global_threads_state.dart';
import '../../../modules/lobby/ui/global_threads_view.dart'
    show ThreadRowAction;
import '../../../modules/lobby/ui/room_grid_layout.dart';
import '../../../shared/thread_properties_dialog.dart';
import '../../../stores/labels_state.dart';
import '../../chat/static_backend.dart';
import '../model.dart';
import '../store.dart';
import 'catalog_view.dart';
import 'common.dart';
import 'threads/threads_view.dart';

/// What the lobby shows; kept in the URL's `view` parameter, so coming back
/// from a dataset or a thread lands where the user left.
enum LobbyView {
  rooms,
  threads,
  datasets;

  static LobbyView parse(String? value) =>
      values.where((v) => v.name == value).firstOrNull ?? rooms;

  String get location =>
      this == rooms ? AppRoutes.lobby : '${AppRoutes.lobby}?view=$name';
}

/// The lobby with threads and datasets beside rooms: rooms are presets to
/// start from, threads every conversation wherever it lives, datasets the
/// catalog to pick from.
class DatasetsLobbyScreen extends StatelessWidget {
  const DatasetsLobbyScreen({
    required this.entry,
    required this.view,
    super.key,
  });

  final ServerEntry entry;
  final LobbyView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < SoliplexBreakpoints.tablet;
    // Three segments beside the title and the create button need a desktop's
    // width; below it the switch takes a row of its own.
    final toggleOwnRow = width < SoliplexBreakpoints.desktop;
    final toggle = SegmentedButton<LobbyView>(
      segments: [
        for (final (value, label, icon) in const [
          (LobbyView.rooms, 'Rooms', Icons.meeting_room_outlined),
          (LobbyView.threads, 'Threads', Icons.forum_outlined),
          (LobbyView.datasets, 'Datasets', Icons.dataset_outlined),
        ])
          ButtonSegment(
            value: value,
            label: Text(label),
            // On a phone the labels alone fit; icons would push them over.
            icon: narrow ? null : Icon(icon),
          ),
      ],
      selected: {view},
      showSelectedIcon: false,
      onSelectionChanged: (s) => context.go(s.first.location),
    );
    final (label, icon, location) = view == LobbyView.datasets
        ? ('New dataset', Icons.add, '/datasets/new')
        : (
            'New conversation',
            Icons.add_comment_outlined,
            '${conversationsLocation()}?new',
          );
    final create = narrow
        ? IconButton.filled(
            tooltip: label,
            icon: Icon(icon),
            onPressed: () => context.go(location),
          )
        : SoliplexButton.filled(
            onPressed: () => context.go(location),
            icon: Icon(icon),
            child: Text(label),
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
                  if (!toggleOwnRow) toggle,
                  const SizedBox(width: SoliplexSpacing.s3),
                  create,
                ],
              ),
            ),
            if (toggleOwnRow)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SoliplexSpacing.s4,
                  vertical: SoliplexSpacing.s2,
                ),
                child: toggle,
              ),
            const Divider(height: 1),
            Expanded(
              child: switch (view) {
                LobbyView.rooms => _RoomGrid(serverAlias: entry.alias),
                LobbyView.threads => _ThreadsView(entry: entry),
                LobbyView.datasets => CatalogView(
                    onOpen: (d) => context.go('/datasets/${d.id}'),
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Every thread the user has, in rooms or not: the app's own cross-room
/// listing state on the static backend, under a copy of its view that can
/// tell the two apart. A conversation outside any room reads "No room"
/// where a thread names its room.
class _ThreadsView extends StatefulWidget {
  const _ThreadsView({required this.entry});

  final ServerEntry entry;

  @override
  State<_ThreadsView> createState() => _ThreadsViewState();
}

class _ThreadsViewState extends State<_ThreadsView> {
  late final _labels = LabelsState(entryResolver: (_) => widget.entry)
    ..setServer(widget.entry.serverId);
  late final _threads = GlobalThreadsState(entryResolver: (_) => widget.entry)
    ..setServer(widget.entry.serverId);

  @override
  void dispose() {
    _threads.dispose();
    _labels.dispose();
    super.dispose();
  }

  Future<void> _onAction(ThreadInfo thread, ThreadRowAction action) async {
    switch (action) {
      // Properties edits the name too, so rename needs no dialog of its own.
      case ThreadRowAction.properties || ThreadRowAction.rename:
        await showDialog<void>(
          context: context,
          builder: (_) => ThreadPropertiesDialog(
            thread: thread,
            labels: _labels.catalogue,
            onSave: ({
              required name,
              required description,
              required labelIds,
            }) =>
                _threads.saveProperties(
              thread,
              name: name,
              description: description,
              labelIds: labelIds,
            ),
          ),
        );
      case ThreadRowAction.delete:
        final confirmed = await showConfirmDialog(
          context,
          title: 'Delete thread?',
          message: 'This removes "${thread.name}" and its messages.',
          confirmLabel: 'Delete',
          isDestructive: true,
        );
        if (confirmed) await _threads.delete(thread);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = DatasetsScope.of(context);
    return ThreadsView(
      state: _threads,
      labels: _labels,
      api: widget.entry.connection.api as StaticSoliplexApi,
      roomNames: {
        for (final p in store.presets.values) p.roomId: p.name,
      },
      roomlessId: conversationsRoomId,
      onThreadTap: (roomId, threadId) => context.go(
        roomId == conversationsRoomId
            ? conversationsLocation(threadId)
            : AppRoutes.thread(widget.entry.alias, roomId, threadId),
      ),
      onThreadAction: _onAction,
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
