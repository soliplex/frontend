import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../model.dart';
import '../store.dart';

/// A level's marking pill.
class LevelBadge extends StatelessWidget {
  const LevelBadge(this.level, {super.key});

  final String level;

  @override
  Widget build(BuildContext context) =>
      SoliplexClassificationBadge(classification: level);
}

/// Puts [level] as the default marking for everything under it, so the
/// app's own classification band — which shows the default — shows the
/// room's ceiling with no change of its own.
class CeilingScope extends StatelessWidget {
  const CeilingScope({required this.level, required this.child, super.key});

  final String level;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final classifications = ClassificationTheme.of(context);
    if (!classifications.isConfigured) return child;
    return Theme(
      data: theme.copyWith(
        extensions: [
          ...theme.extensions.values.where((e) => e is! ClassificationTheme),
          classifications.copyWith(defaultId: level),
        ],
      ),
      child: child,
    );
  }
}

/// `namespace/name`, monospace, the namespace muted so the name reads first.
class DatasetLabel extends StatelessWidget {
  const DatasetLabel(this.dataset, {super.key, this.style});

  final Dataset dataset;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = context.monospaceOn(style ?? theme.textTheme.bodySmall);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${dataset.namespace}/',
            style: base.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          TextSpan(text: dataset.slug, style: base),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// The dataset's state as a pill: what a thread using it would get.
class DatasetStatusBadge extends StatelessWidget {
  const DatasetStatusBadge(this.dataset, {super.key, this.showPrivate = false});

  final Dataset dataset;

  /// Mark the owner's own unshared datasets.
  final bool showPrivate;

  @override
  Widget build(BuildContext context) {
    final d = dataset;
    if (d.isDeprecated) {
      return Tooltip(
        message: d.deprecation!.reason,
        child: const SoliplexBadge(
          label: Text('Deprecated'),
          icon: Icon(Icons.history_toggle_off),
          intent: BadgeIntent.warning,
        ),
      );
    }
    final status = switch (d.status) {
      DatasetStatus.empty => const SoliplexBadge(label: Text('Empty')),
      DatasetStatus.searchable => const SoliplexBadge(
          label: Text('Searchable'),
          icon: Icon(Icons.manage_search),
          intent: BadgeIntent.success,
        ),
      DatasetStatus.ingesting => Tooltip(
          message: 'Until ingestion finishes, threads get the raw files in '
              'the agent sandbox but no search over them.',
          child: SoliplexBadge(
            label: Text(
              'Ingesting ${d.ingestibleDone}/${d.ingestibleTotal} · '
              'raw files only',
            ),
            icon: const Icon(Icons.hourglass_top),
            intent: BadgeIntent.warning,
          ),
        ),
      DatasetStatus.sandboxOnly => const SoliplexBadge(
          label: Text('Sandbox only'),
          icon: Icon(Icons.inventory_2_outlined),
          intent: BadgeIntent.info,
        ),
    };
    if (!showPrivate || d.isShared) return status;
    return Wrap(
      spacing: SoliplexSpacing.s1,
      runSpacing: SoliplexSpacing.s1,
      children: [
        status,
        const SoliplexBadge(
          label: Text('Private'),
          icon: Icon(Icons.lock_person_outlined),
        ),
      ],
    );
  }
}

/// One file's place in ingestion.
class FileStatusBadge extends StatelessWidget {
  const FileStatusBadge(this.file, {super.key});

  final DatasetFile file;

  @override
  Widget build(BuildContext context) => switch (file.status) {
        FileStatus.queued => const SoliplexBadge(
            label: Text('Queued'),
            icon: Icon(Icons.hourglass_empty),
          ),
        FileStatus.ingesting => SoliplexBadge(
            label: Text('Ingesting ${(file.progress * 100).round()}%'),
            icon: const Icon(Icons.sync),
            intent: BadgeIntent.info,
          ),
        FileStatus.searchable => const SoliplexBadge(
            label: Text('Searchable'),
            intent: BadgeIntent.success,
          ),
        FileStatus.sandboxOnly => const Tooltip(
            message: 'CSV and other non-ingestible types reach the agent as '
                'raw files only.',
            child: SoliplexBadge(
              label: Text('Sandbox only'),
              intent: BadgeIntent.info,
            ),
          ),
      };
}

/// A file someone has called out as outdated. The tooltip says why, and that
/// the file is still searchable — the mark travels with it rather than
/// removing it.
class OutdatedBadge extends StatelessWidget {
  const OutdatedBadge(this.mark, {super.key});

  final OutdatedMark mark;

  @override
  Widget build(BuildContext context) {
    final store = DatasetsScope.read(context);
    final by = store.principals[mark.by]?.name ?? mark.by;
    return Tooltip(
      message: [
        'Marked outdated by $by ${formatAgo(mark.at)}: ${mark.reason}',
        if (mark.replacedBy != null) 'Use ${mark.replacedBy} instead.',
        'Still searchable: the agent sees this mark with anything it '
            'retrieves from the file.',
      ].join('\n'),
      child: const SoliplexBadge(
        label: Text('Outdated'),
        icon: Icon(Icons.history_toggle_off),
        intent: BadgeIntent.warning,
      ),
    );
  }
}

/// A disclaimer box: the system does not check this, the user does.
class Notice extends StatelessWidget {
  const Notice({
    required this.text,
    super.key,
    this.icon = Icons.info_outline,
    this.warning = false,
  });

  final String text;
  final IconData icon;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final soliplex = SoliplexTheme.of(context).colors;
    final background =
        warning ? soliplex.warningContainer : soliplex.infoContainer;
    final foreground =
        warning ? soliplex.onWarningContainer : soliplex.onInfoContainer;
    return Container(
      padding: const EdgeInsets.all(SoliplexSpacing.s3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(context.radii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

String formatBytes(int bytes) {
  if (bytes < 1000) return '$bytes B';
  if (bytes < 1000000) return '${(bytes / 1000).round()} KB';
  if (bytes < 1000000000) return '${(bytes / 1000000).toStringAsFixed(1)} MB';
  return '${(bytes / 1000000000).toStringAsFixed(1)} GB';
}

String formatAgo(DateTime at) {
  final d = DateTime.now().difference(at);
  if (d.inDays >= 365) return '${d.inDays ~/ 365}y ago';
  if (d.inDays >= 30) return '${d.inDays ~/ 30}mo ago';
  if (d.inDays >= 1) return '${d.inDays}d ago';
  if (d.inHours >= 1) return '${d.inHours}h ago';
  return 'just now';
}

/// "ops/pumps, plant/valves +2"-style summary of labels.
String summarizeLabels(List<String> labels, {int shown = 2}) {
  if (labels.length <= shown) return labels.join(', ');
  return '${labels.take(shown).join(', ')} +${labels.length - shown}';
}
