import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../../../modules/room/ui/room_info/room_info_widgets.dart';
import '../classification_levels.dart';
import '../model.dart';
import '../store.dart';
import 'common.dart';
import 'share_dialogs.dart';

/// One dataset: what it is, who has it, and where each of its files is on
/// the way to being searchable. The owner uploads, shares and deprecates
/// from here.
class DatasetDetailScreen extends StatelessWidget {
  const DatasetDetailScreen({required this.datasetId, super.key});

  final String datasetId;

  @override
  Widget build(BuildContext context) {
    final store = DatasetsScope.of(context);
    final d = store.byId(datasetId);
    if (d == null || !store.canAccess(d)) {
      return Scaffold(
        appBar: AppBar(leading: const _BackToCatalog()),
        body: const EmptyMessage(
          label: "This dataset doesn't exist, or isn't shared with you.",
        ),
      );
    }
    final theme = Theme.of(context);
    final owner = store.isOwner(d);
    final narrow =
        MediaQuery.sizeOf(context).width < SoliplexBreakpoints.desktop;

    void upload() => context.go('/datasets/${d.id}/upload');
    final actions = owner
        ? <Widget>[
            if (!narrow) ...[
              Tooltip(
                message: d.isDeprecated
                    ? "Deprecated datasets can't be newly shared"
                    : '',
                child: SoliplexButton.outlined(
                  onPressed:
                      d.isDeprecated ? null : () => showShareDialog(context, d),
                  icon: const Icon(Icons.group_add_outlined),
                  child: const Text('Share'),
                ),
              ),
            ],
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) => switch (v) {
                'share' => showShareDialog(context, d),
                _ => showDeprecateDialog(context, d),
              },
              itemBuilder: (_) => [
                if (narrow) ...[
                  PopupMenuItem(
                    value: 'share',
                    enabled: !d.isDeprecated,
                    child: const Text('Share'),
                  ),
                ],
                PopupMenuItem(
                  value: 'deprecate',
                  enabled: !d.isDeprecated,
                  child: const Text('Deprecate…'),
                ),
              ],
            ),
            const SizedBox(width: SoliplexSpacing.s2),
          ]
        : const <Widget>[];

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: SoliplexSpacing.s2,
          runSpacing: SoliplexSpacing.s1,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            LevelBadge(d.level),
            DatasetStatusBadge(d, showPrivate: owner),
          ],
        ),
        const SizedBox(height: SoliplexSpacing.s2),
        DatasetLabel(d, style: theme.textTheme.titleMedium),
        Text(d.title, style: theme.textTheme.headlineMedium),
        if (d.description.isNotEmpty) ...[
          const SizedBox(height: SoliplexSpacing.s1),
          Text(
            d.description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );

    final side = [
      _About(dataset: d),
      _Ingestion(dataset: d),
    ];
    final files = d.files.isEmpty
        ? _EmptyFiles(onUpload: upload)
        : _FilesTable(dataset: d, compact: narrow, onUpload: upload);

    return Scaffold(
      appBar: AppBar(
        leading: const _BackToCatalog(),
        title: const Text('Dataset'),
        actions: actions,
      ),
      body: ListView(
        padding: const EdgeInsets.all(SoliplexSpacing.s4),
        children: [
          if (d.deprecation case final deprecation?) ...[
            _DeprecatedBanner(dataset: d, deprecation: deprecation),
            const SizedBox(height: SoliplexSpacing.s4),
          ],
          header,
          const SizedBox(height: SoliplexSpacing.s4),
          if (narrow) ...[
            ...side,
            files,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: files),
                const SizedBox(width: SoliplexSpacing.s4),
                SizedBox(width: 320, child: Column(children: side)),
              ],
            ),
        ],
      ),
    );
  }
}

class _BackToCatalog extends StatelessWidget {
  const _BackToCatalog();

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Back to the catalog',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.canPop()
            ? context.pop()
            : context.go('/lobby?view=datasets'),
      );
}

class _About extends StatelessWidget {
  const _About({required this.dataset});

  final Dataset dataset;

  @override
  Widget build(BuildContext context) {
    final store = DatasetsScope.of(context);
    final d = dataset;
    final people = d.audience
        .where((id) => store.principals[id]?.kind == PrincipalKind.person)
        .length;
    final groups = d.audience.length - people;
    final audience = !d.isShared
        ? 'Private — only you'
        : [
            if (people > 0) '$people ${people == 1 ? 'person' : 'people'}',
            if (groups > 0) '$groups ${groups == 1 ? 'group' : 'groups'}',
          ].join(', ');
    return SectionCard(
      title: 'About',
      children: [
        InfoRow(label: 'Level', value: levelLabel(d.level)),
        InfoRow(label: 'Namespace', value: d.namespace),
        InfoRow(label: 'Owner', value: store.ownerName(d)),
        InfoRow(label: 'Created', value: formatAgo(d.createdAt)),
        InfoRow(label: 'Audience', value: audience),
        InfoRow(label: 'Keywords', value: _list(d.tags.keywords)),
        InfoRow(label: 'Systems', value: _list(d.tags.systems)),
        InfoRow(label: 'Affiliation', value: _list(d.tags.affiliations)),
      ],
    );
  }

  static String _list(Set<String> values) =>
      values.isEmpty ? '—' : values.join(', ');
}

class _Ingestion extends StatelessWidget {
  const _Ingestion({required this.dataset});

  final Dataset dataset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = dataset;
    final total = d.ingestibleTotal;
    final done = d.ingestibleDone;
    final text = switch (d.status) {
      DatasetStatus.empty => 'Nothing to ingest yet.',
      DatasetStatus.sandboxOnly =>
        'Only raw-file types: threads get them in the agent sandbox, never '
            'as search.',
      DatasetStatus.searchable => 'All $total ingestible files are '
          'searchable.',
      DatasetStatus.ingesting => '$done of $total ingestible files '
          'searchable. Until ingestion finishes, threads using this dataset '
          'get the raw files in the agent sandbox but no search over them.',
    };
    return SectionCard(
      title: 'Ingestion',
      children: [
        if (total > 0) ...[
          LinearProgressIndicator(value: done / total),
          const SizedBox(height: SoliplexSpacing.s2),
        ],
        Text(text, style: theme.textTheme.bodySmall),
        if (d.sandboxOnlyCount > 0) ...[
          const SizedBox(height: SoliplexSpacing.s2),
          Text(
            '${d.sandboxOnlyCount} sandbox-only '
            '${d.sandboxOnlyCount == 1 ? 'file' : 'files'} (not ingested for '
            'search).',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _DeprecatedBanner extends StatelessWidget {
  const _DeprecatedBanner({required this.dataset, required this.deprecation});

  final Dataset dataset;
  final Deprecation deprecation;

  @override
  Widget build(BuildContext context) {
    final store = DatasetsScope.of(context);
    final replacement = deprecation.replacedById == null
        ? null
        : store.byId(deprecation.replacedById!);
    final by = store.principals[deprecation.by]?.name ?? deprecation.by;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Notice(
          warning: true,
          icon: Icons.history_toggle_off,
          text: 'Deprecated by $by ${formatAgo(deprecation.at)}: '
              '${deprecation.reason} It is hidden from the catalog and '
              "can't be newly shared; threads already using it keep working "
              'and show a warning.',
        ),
        if (replacement != null)
          SoliplexButton.text(
            isCompact: true,
            onPressed: () => context.go('/datasets/${replacement.id}'),
            icon: const Icon(Icons.arrow_forward),
            child: Text('Replaced by ${replacement.label}'),
          ),
      ],
    );
  }
}

class _EmptyFiles extends StatelessWidget {
  const _EmptyFiles({required this.onUpload});

  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(SoliplexSpacing.s6),
        child: Column(
          children: [
            const EmptyMessage(
              label: 'No files yet. Upload files to make this dataset '
                  'useful.',
            ),
            _UploadButton(onPressed: onUpload),
          ],
        ),
      ),
    );
  }
}

class _FilesTable extends StatelessWidget {
  const _FilesTable({
    required this.dataset,
    required this.compact,
    required this.onUpload,
  });

  final Dataset dataset;
  final bool compact;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final files = [...dataset.files]
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    final outdated = dataset.outdatedCount;
    final header = Padding(
      padding: const EdgeInsets.all(SoliplexSpacing.s3),
      child: Wrap(
        spacing: SoliplexSpacing.s3,
        runSpacing: SoliplexSpacing.s2,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            [
              '${files.length} files',
              formatBytes(dataset.sizeBytes),
              if (outdated > 0) '$outdated marked outdated',
            ].join(' · '),
            style: theme.textTheme.titleSmall,
          ),
          _UploadButton(onPressed: onUpload),
        ],
      ),
    );
    if (compact) {
      return Card(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            for (final f in files)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(
                  left: SoliplexSpacing.s4,
                ),
                title: Text(f.name, overflow: TextOverflow.ellipsis),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${f.type} · ${formatBytes(f.sizeBytes)} · '
                      '${formatAgo(f.addedAt)}',
                    ),
                    if (f.outdated != null) OutdatedBadge(f.outdated!),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FileStatusBadge(f),
                    _FileMenu(dataset: dataset, file: f),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Table(
            columnWidths: const {
              0: FlexColumnWidth(4),
              1: FlexColumnWidth(),
              2: FlexColumnWidth(1.2),
              3: IntrinsicColumnWidth(),
              4: FlexColumnWidth(2),
              5: FlexColumnWidth(1.2),
              6: IntrinsicColumnWidth(),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
                children: [
                  for (final h in const [
                    'Name',
                    'Type',
                    'Size',
                    'Level',
                    'Status',
                    'Added',
                  ])
                    _cell(Text(h, style: theme.textTheme.labelMedium)),
                  const SizedBox.shrink(),
                ],
              ),
              for (final f in files)
                TableRow(
                  children: [
                    _cell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.name, overflow: TextOverflow.ellipsis),
                          if (f.outdated != null) ...[
                            const SizedBox(height: SoliplexSpacing.s1),
                            OutdatedBadge(f.outdated!),
                          ],
                          if (f.status == FileStatus.ingesting)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: SoliplexSpacing.s1,
                              ),
                              child: LinearProgressIndicator(value: f.progress),
                            ),
                        ],
                      ),
                    ),
                    _cell(Text(f.type, style: muted)),
                    _cell(Text(formatBytes(f.sizeBytes), style: muted)),
                    _cell(LevelBadge(f.level)),
                    _cell(
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FileStatusBadge(f),
                      ),
                    ),
                    _cell(Text(formatAgo(f.addedAt), style: muted)),
                    _FileMenu(dataset: dataset, file: f),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _cell(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SoliplexSpacing.s3,
          vertical: SoliplexSpacing.s2,
        ),
        child: child,
      );
}

/// Where files get into the dataset — the only upload on this page.
///
/// Says "dataset" because the app has other uploads that look alike: the
/// composer's attach goes to one thread, and a room's info page used to take
/// files for the room. This one makes files searchable by every thread that
/// uses the dataset.
class _UploadButton extends StatelessWidget {
  const _UploadButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SoliplexButton.filled(
        onPressed: onPressed,
        icon: const Icon(Icons.upload_file, size: 18),
        child: const Text('Upload to dataset'),
      );
}

/// A file's own actions: calling it out as outdated, or taking that back.
class _FileMenu extends StatelessWidget {
  const _FileMenu({required this.dataset, required this.file});

  final Dataset dataset;
  final DatasetFile file;

  @override
  Widget build(BuildContext context) {
    final store = DatasetsScope.read(context);
    final marked = file.outdated != null;
    return PopupMenuButton<bool>(
      tooltip: 'File actions',
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (_) => marked
          ? store.clearOutdated(file)
          : showOutdatedDialog(context, dataset, file),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: true,
          child: Text(marked ? 'Clear outdated mark' : 'Mark outdated…'),
        ),
      ],
    );
  }
}
