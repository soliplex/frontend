import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../../chat/thread_panel/panel_section.dart';
import '../model.dart';
import '../store.dart';
import 'catalog_view.dart';
import 'common.dart';

/// The thread's datasets, for the chat screen: the panel segment that lists
/// them and the summary row above the composer.
ThreadDatasetsSeam threadDatasetsSeam(DatasetsStore store) {
  return ThreadDatasetsSeam(
    listenable: store,
    section: (context, scope) {
      final tray = _Tray.of(store, scope);
      return PanelSection(
        title: 'Datasets',
        icon: Icons.dataset_outlined,
        summary: [
          '${tray.datasets.length} in use',
          if (tray.rawOnly > 0) '${tray.rawOnly} raw only',
          if (scope.hasMessages) 'fixed',
        ].join(' · '),
        handleCount: tray.datasets.length,
        body: (_) => _TrayBody(scope: scope),
      );
    },
    composerAccessory: (context, scope, openPanel) =>
        _ComposerSummary(scope: scope, onTap: openPanel),
  );
}

/// What a thread — or the room's next thread — uses, resolved.
class _Tray {
  _Tray(this.ids, this.datasets, this.preset);

  factory _Tray.of(DatasetsStore store, ThreadScope scope) {
    final ids = store.trayFor(scope.roomId, scope.threadId);
    return _Tray(
      ids,
      [for (final id in ids) store.byId(id)].nonNulls.toList(),
      store.preset(scope.roomId),
    );
  }

  final List<String> ids;
  final List<Dataset> datasets;
  final RoomPreset? preset;

  int get rawOnly => datasets.where((d) => d.isRawOnly).length;
  List<Dataset> get deprecated =>
      datasets.where((d) => d.isDeprecated).toList();
}

class _TrayBody extends StatelessWidget {
  const _TrayBody({required this.scope});

  final ThreadScope scope;

  @override
  Widget build(BuildContext context) {
    final store = DatasetsScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tray = _Tray.of(store, scope);
    final preset = tray.preset;
    final locked = scope.hasMessages;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final pinned = [
      for (final d in store.pinned)
        if (!tray.ids.contains(d.id) &&
            !d.isDeprecated &&
            (preset == null || isWithin(d.level, preset.ceiling)))
          d,
    ];

    Future<void> add() async {
      if (preset == null) return;
      final picked = await showDatasetPicker(
        context,
        ceiling: preset.ceiling,
        inUse: tray.ids.toSet(),
      );
      for (final id in picked ?? const <String>[]) {
        store.addToTray(scope.roomId, scope.threadId, id);
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        SoliplexSpacing.s4,
        0,
        SoliplexSpacing.s4,
        SoliplexSpacing.s3,
      ),
      children: [
        if (preset != null)
          Row(
            children: [
              Text('Room level', style: theme.textTheme.labelSmall),
              const SizedBox(width: SoliplexSpacing.s2),
              LevelBadge(preset.ceiling),
              const SizedBox(width: SoliplexSpacing.s2),
              Expanded(
                child: Text('datasets above it are locked', style: muted),
              ),
            ],
          ),
        const SizedBox(height: SoliplexSpacing.s2),
        if (tray.datasets.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s3),
            child: Text(
              'No datasets: the agent answers without retrieval.',
              style: muted,
            ),
          ),
        for (final d in tray.datasets)
          _TrayRow(
            dataset: d,
            isDefault: preset?.defaultDatasetIds.contains(d.id) ?? false,
            replacement: d.deprecation?.replacedById == null
                ? null
                : store.byId(d.deprecation!.replacedById!),
            onOpen: () => context.go('/datasets/${d.id}'),
            onRemove: locked
                ? null
                : () =>
                    store.removeFromTray(scope.roomId, scope.threadId, d.id),
          ),
        if (tray.rawOnly > 0) ...[
          const SizedBox(height: SoliplexSpacing.s2),
          Notice(
            warning: true,
            icon: Icons.hourglass_top,
            text: '${tray.rawOnly == 1 ? '1 dataset is' : '${tray.rawOnly} '
                    'datasets are'} not searchable yet: the agent gets the raw '
                'files in its sandbox, without search over them.',
          ),
        ],
        const SizedBox(height: SoliplexSpacing.s3),
        if (!locked) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: SoliplexButton.outlined(
              onPressed: add,
              icon: const Icon(Icons.add),
              child: const Text('Add datasets'),
            ),
          ),
          if (pinned.isNotEmpty) ...[
            const SizedBox(height: SoliplexSpacing.s3),
            Text('Pinned', style: theme.textTheme.labelSmall),
            const SizedBox(height: SoliplexSpacing.s1),
            Wrap(
              spacing: SoliplexSpacing.s2,
              runSpacing: SoliplexSpacing.s2,
              children: [
                for (final d in pinned)
                  SoliplexChip.action(
                    icon: const Icon(Icons.add),
                    label: Text(d.label),
                    onPressed: () =>
                        store.addToTray(scope.roomId, scope.threadId, d.id),
                  ),
              ],
            ),
          ],
          const SizedBox(height: SoliplexSpacing.s3),
          Text(
            'You can change datasets until you send the first message.',
            style: muted,
          ),
        ] else
          _LockedNotice(
            onNewThread: () {
              store.startNewThreadWith(scope.roomId, tray.ids);
              // From the sheet, close it first: the new thread is behind it.
              Navigator.of(context).popUntil((r) => r is! PopupRoute);
              scope.newThread();
            },
          ),
      ],
    );
  }
}

class _TrayRow extends StatelessWidget {
  const _TrayRow({
    required this.dataset,
    required this.isDefault,
    required this.replacement,
    required this.onOpen,
    required this.onRemove,
  });

  final Dataset dataset;
  final bool isDefault;
  final Dataset? replacement;
  final VoidCallback onOpen;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = dataset;
    final chips = <Widget>[
      if (isDefault) const SoliplexBadge(label: Text('Room default')),
      if (d.isRawOnly)
        Tooltip(
          message: d.status == DatasetStatus.sandboxOnly
              ? 'Only raw-file types: the agent reads them in its sandbox.'
              : 'Ingestion ${d.ingestibleDone}/${d.ingestibleTotal}. The '
                  "agent can read the raw files but can't search them yet.",
          child: const SoliplexBadge(
            label: Text('Raw files only'),
            intent: BadgeIntent.warning,
          ),
        ),
      if (d.outdatedCount > 0)
        Tooltip(
          message: '${d.outdatedCount} '
              '${d.outdatedCount == 1 ? 'file is' : 'files are'} marked '
              'outdated. They are still searched; the agent sees the mark.',
          child: SoliplexBadge(
            label: Text('${d.outdatedCount} outdated'),
            intent: BadgeIntent.warning,
          ),
        ),
      if (d.isDeprecated)
        Tooltip(
          message: [
            d.deprecation!.reason,
            if (replacement != null) 'Consider ${replacement!.label}.',
          ].join(' '),
          child: const SoliplexBadge(
            label: Text('Deprecated'),
            intent: BadgeIntent.warning,
          ),
        ),
    ];
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(context.radii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LevelBadge(d.level),
            const SizedBox(width: SoliplexSpacing.s2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DatasetLabel(d),
                  Text(
                    d.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (chips.isNotEmpty) ...[
                    const SizedBox(height: SoliplexSpacing.s1),
                    Wrap(
                      spacing: SoliplexSpacing.s1,
                      runSpacing: SoliplexSpacing.s1,
                      children: chips,
                    ),
                  ],
                ],
              ),
            ),
            if (onRemove != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Remove from this thread',
                icon: const Icon(Icons.close, size: 18),
                onPressed: onRemove,
              ),
          ],
        ),
      ),
    );
  }
}

class _LockedNotice extends StatelessWidget {
  const _LockedNotice({required this.onNewThread});

  final VoidCallback onNewThread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(SoliplexSpacing.s3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(context.radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline,
                  size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: SoliplexSpacing.s2),
              Expanded(
                child: Text(
                  'Datasets are fixed once a conversation starts, so '
                  'citations and summaries stay consistent.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: SoliplexSpacing.s2),
          SoliplexButton.text(
            isCompact: true,
            onPressed: onNewThread,
            icon: const Icon(Icons.add_comment_outlined),
            child: const Text('New thread with these datasets'),
          ),
        ],
      ),
    );
  }
}

/// One line above the composer: what the next message searches.
class _ComposerSummary extends StatelessWidget {
  const _ComposerSummary({required this.scope, required this.onTap});

  final ThreadScope scope;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = DatasetsScope.of(context);
    final theme = Theme.of(context);
    final tray = _Tray.of(store, scope);
    final issues = [
      if (tray.rawOnly > 0) '${tray.rawOnly} raw only',
      if (tray.deprecated.isNotEmpty) '${tray.deprecated.length} deprecated',
    ];
    final color =
        issues.isEmpty ? theme.colorScheme.onSurfaceVariant : context.warning;
    final style = theme.textTheme.labelMedium?.copyWith(color: color);
    final n = tray.datasets.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(context.radii.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SoliplexSpacing.s2,
            vertical: SoliplexSpacing.s1,
          ),
          child: Row(
            children: [
              Icon(Icons.dataset_outlined, size: 16, color: color),
              const SizedBox(width: SoliplexSpacing.s2),
              Expanded(
                child: Text(
                  [
                    if (n == 1) '1 dataset' else '$n datasets',
                    if (n > 0)
                      summarizeLabels([for (final d in tray.datasets) d.label]),
                    ...issues,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
              if (scope.hasMessages) ...[
                const SizedBox(width: SoliplexSpacing.s2),
                Tooltip(
                  message: 'Fixed for this thread',
                  child: Icon(Icons.lock_outline, size: 16, color: color),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
