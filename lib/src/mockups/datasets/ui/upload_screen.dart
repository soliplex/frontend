import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../../../core/layout.dart';
import '../../../modules/room/pick_file.dart';
import '../classification_levels.dart';
import '../model.dart';
import '../store.dart';
import '../upload_session.dart';
import 'common.dart';

/// Uploading into a dataset, in three steps: choose the files and declare
/// their level, read what the scan made of them, then commit — which can't
/// be undone.
class UploadScreen extends StatefulWidget {
  const UploadScreen({required this.datasetId, super.key});

  final String datasetId;

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  UploadSession? _session;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final d = DatasetsScope.read(context).byId(widget.datasetId);
    if (_session == null && d != null) {
      _session = UploadSession(dataset: d)..addListener(_changed);
    }
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  Future<void> _pick(Future<PickFilesResult?> Function() picker) async {
    final session = _session!;
    try {
      final result = await picker();
      if (result == null) return;
      session.add([
        for (final f in result.files)
          StagedFile(
            name: f.name,
            sizeBytes: f.size,
            declaredLevel: session.dataset.level,
          ),
      ]);
    } on PickFileException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the file picker.')),
      );
    }
  }

  void _commit() {
    final session = _session!;
    final store = DatasetsScope.read(context);
    final count = session.included.length;
    store.commitUpload(session.dataset, session.files);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$count ${count == 1 ? 'file' : 'files'} committed. Ingestion '
          'scheduled.',
        ),
      ),
    );
    context.go('/datasets/${session.dataset.id}');
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) {
      return const Scaffold(body: Center(child: Text('No such dataset')));
    }
    final d = session.dataset;
    final theme = Theme.of(context);
    final level = levelLabel(d.level);
    final body = switch (session.step) {
      UploadStep.choose => _ChooseStep(
          session: session,
          onPickFiles: () => _pick(pickFiles),
          onPickFolder: () => _pick(pickFolder),
          onSamples: () => session.add(sampleUpload(d.level)),
        ),
      UploadStep.scan => _ScanStep(session: session),
      UploadStep.review => _ReviewStep(session: session),
    };
    final (String label, VoidCallback? action) = switch (session.step) {
      UploadStep.choose => (
          'Scan ${session.files.length} '
              '${session.files.length == 1 ? 'file' : 'files'}',
          session.files.isEmpty ? null : session.startScan,
        ),
      UploadStep.scan => (
          'Continue to review',
          session.scanning || session.unresolved > 0 ? null : session.toReview,
        ),
      UploadStep.review => (
          'Commit ${session.included.length} '
              '${session.included.length == 1 ? 'file' : 'files'}',
          session.canCommit ? _commit : null,
        ),
    };
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to the dataset',
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/datasets/${d.id}'),
        ),
        title: const Text('Upload to dataset'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: formColumnMaxWidth + 200),
          child: ListView(
            padding: const EdgeInsets.all(SoliplexSpacing.s4),
            children: [
              Row(
                children: [
                  LevelBadge(d.level),
                  const SizedBox(width: SoliplexSpacing.s2),
                  Expanded(
                    child: DatasetLabel(d, style: theme.textTheme.titleMedium),
                  ),
                ],
              ),
              const SizedBox(height: SoliplexSpacing.s1),
              Text(
                'Files declared above $level are rejected.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (session.step == UploadStep.choose) ...[
                const SizedBox(height: SoliplexSpacing.s3),
                const Notice(
                  icon: Icons.upload_file,
                  text: 'Files added here join the dataset: every thread that '
                      'uses it can search them, and they stay for good. To '
                      'use a file in one conversation only, attach it in the '
                      'thread instead.',
                ),
              ],
              const SizedBox(height: SoliplexSpacing.s4),
              _Steps(step: session.step),
              const SizedBox(height: SoliplexSpacing.s4),
              body,
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(SoliplexSpacing.s3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (session.step != UploadStep.choose)
                SoliplexButton.text(
                  onPressed: session.back,
                  child: const Text('Back'),
                ),
              const SizedBox(width: SoliplexSpacing.s2),
              Flexible(
                child: SoliplexButton.filled(
                  onPressed: action,
                  isLoading:
                      session.step == UploadStep.scan && session.scanning,
                  child: Text(label, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.step});

  final UploadStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const names = ['Choose files', 'Scan', 'Review & commit'];
    return Wrap(
      spacing: SoliplexSpacing.s4,
      runSpacing: SoliplexSpacing.s2,
      children: [
        for (final (i, name) in names.indexed)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: i <= step.index
                    ? scheme.primary
                    : scheme.surfaceContainerHighest,
                child: i < step.index
                    ? Icon(Icons.check, size: 14, color: scheme.onPrimary)
                    : Text(
                        '${i + 1}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: i == step.index
                              ? scheme.onPrimary
                              : scheme.onSurface,
                        ),
                      ),
              ),
              const SizedBox(width: SoliplexSpacing.s2),
              Text(
                name,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: i == step.index ? scheme.onSurface : scheme.outline,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _ChooseStep extends StatelessWidget {
  const _ChooseStep({
    required this.session,
    required this.onPickFiles,
    required this.onPickFolder,
    required this.onSamples,
  });

  final UploadSession session;
  final VoidCallback onPickFiles;
  final VoidCallback onPickFolder;
  final VoidCallback onSamples;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: SoliplexSpacing.s2,
          runSpacing: SoliplexSpacing.s2,
          children: [
            SoliplexButton.outlined(
              onPressed: onPickFiles,
              icon: const Icon(Icons.upload_file),
              child: const Text('Choose files…'),
            ),
            SoliplexButton.outlined(
              onPressed: onPickFolder,
              icon: const Icon(Icons.drive_folder_upload),
              child: const Text('Choose folder…'),
            ),
            SoliplexButton.text(
              onPressed: onSamples,
              icon: const Icon(Icons.auto_awesome_outlined),
              child: const Text('Add sample files'),
            ),
          ],
        ),
        const SizedBox(height: SoliplexSpacing.s3),
        if (session.files.isEmpty)
          Padding(
            padding: const EdgeInsets.all(SoliplexSpacing.s6),
            child: Text(
              'No files chosen yet. Declare each file’s level: the scan '
              'checks it against the dataset’s.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final f in session.files)
          Card(
            margin: const EdgeInsets.only(bottom: SoliplexSpacing.s2),
            child: Padding(
              padding: const EdgeInsets.all(SoliplexSpacing.s3),
              child: Wrap(
                spacing: SoliplexSpacing.s3,
                runSpacing: SoliplexSpacing.s2,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.name, overflow: TextOverflow.ellipsis),
                        Text(
                          formatBytes(f.sizeBytes),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SoliplexDropdown<String>(
                        label: 'Declared level',
                        width: 180,
                        initialValue: f.declaredLevel,
                        entries: [
                          for (final id in levelIds)
                            SoliplexDropdownEntry(
                              value: id,
                              label: levelLabel(id),
                            ),
                        ],
                        onSelected: (v) {
                          if (v != null) session.declare(f, v);
                        },
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.close),
                        onPressed: () => session.remove(f),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ScanStep extends StatelessWidget {
  const _ScanStep({required this.session});

  final UploadSession session;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Notice(
          icon: Icons.policy_outlined,
          text: 'The scan looks for classification markings. Its results '
              'are advisory: an unmarked file can still hold more than it '
              'says.',
        ),
        const SizedBox(height: SoliplexSpacing.s3),
        for (final f in session.files) _ScanRow(session: session, file: f),
      ],
    );
  }
}

class _ScanRow extends StatelessWidget {
  const _ScanRow({required this.session, required this.file});

  final UploadSession session;
  final StagedFile file;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final f = file;
    final (IconData icon, Color color, Color? background) = switch (f.status) {
      ScanStatus.pending => (Icons.schedule, scheme.outline, null),
      ScanStatus.scanning => (Icons.radar, context.info, null),
      ScanStatus.clean => (Icons.check_circle_outline, context.success, null),
      ScanStatus.flagged => (Icons.flag_outlined, context.warning, null),
      ScanStatus.rejected => (
          Icons.block,
          scheme.onErrorContainer,
          scheme.errorContainer,
        ),
      ScanStatus.sandboxOnly => (
          Icons.inventory_2_outlined,
          context.info,
          null
        ),
    };
    final textColor =
        background == null ? scheme.onSurfaceVariant : scheme.onErrorContainer;
    return Card(
      margin: const EdgeInsets.only(bottom: SoliplexSpacing.s2),
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(SoliplexSpacing.s3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (f.status == ScanStatus.scanning)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(icon, size: 20, color: color),
            const SizedBox(width: SoliplexSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          f.name,
                          overflow: TextOverflow.ellipsis,
                          style: background == null
                              ? null
                              : theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.onErrorContainer,
                                ),
                        ),
                      ),
                      LevelBadge(f.declaredLevel),
                    ],
                  ),
                  Text(
                    f.advisory ??
                        (f.status == ScanStatus.scanning
                            ? 'Scanning…'
                            : 'Waiting to scan'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: textColor,
                    ),
                  ),
                  if (f.status == ScanStatus.flagged)
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: f.acknowledged,
                              onChanged: (v) =>
                                  session.acknowledge(f, value: v ?? false),
                            ),
                            Flexible(
                              child: Text(
                                'I reviewed this file and it is within '
                                '${levelLabel(session.dataset.level)}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                        SoliplexButton.text(
                          isCompact: true,
                          onPressed: () => session.remove(f),
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({required this.session});

  final UploadSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = session.dataset;
    final level = levelLabel(d.level);
    final included = session.included.toList();
    final counts = [
      '${included.length} ${included.length == 1 ? 'file' : 'files'} will be '
          'added',
      if (session.rejected > 0) '${session.rejected} rejected',
      if (session.sandboxOnly > 0) '${session.sandboxOnly} sandbox only',
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(counts, style: theme.textTheme.titleSmall),
        const SizedBox(height: SoliplexSpacing.s2),
        for (final f in included)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
            child: Row(
              children: [
                Icon(
                  f.status == ScanStatus.sandboxOnly
                      ? Icons.inventory_2_outlined
                      : Icons.description_outlined,
                  size: 18,
                ),
                const SizedBox(width: SoliplexSpacing.s2),
                Expanded(
                  child: Text(f.name, overflow: TextOverflow.ellipsis),
                ),
                Text(
                  formatBytes(f.sizeBytes),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        const SizedBox(height: SoliplexSpacing.s4),
        const Notice(
          warning: true,
          icon: Icons.warning_amber_outlined,
          text: "Uploads can't be undone: files can't be deleted from a "
              'dataset. If one turns out wrong, the dataset can only be '
              'deprecated.',
        ),
        const SizedBox(height: SoliplexSpacing.s3),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: session.attested,
          onChanged: (v) => session.attest(value: v ?? false),
          title: Text(
            'I attest that every file I am adding contains no information '
            'above $level and that I am authorized to place it in '
            '${d.label}.',
            style: theme.textTheme.bodyMedium,
          ),
          subtitle: const Text(
            'Soliplex does not verify classification; scan results are '
            'advisory only.',
          ),
        ),
        const SizedBox(height: SoliplexSpacing.s2),
        Text(
          'After commit, ingestion is scheduled. Until it finishes, threads '
          'using ${d.label} get the raw files without search.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
