import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// Shows where a thread's context tokens are going.
Future<void> showContextBreakdown(
  BuildContext context, {
  required ContextUsage usage,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => ContextBreakdownDialog(usage: usage),
  );
}

/// The breakdown behind the composer's context gauge.
class ContextBreakdownDialog extends StatelessWidget {
  /// Creates the dialog.
  const ContextBreakdownDialog({required this.usage, super.key});

  /// The reading to explain.
  final ContextUsage usage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _entries(context);

    return AlertDialog(
      title: const Text('Context usage'),
      content: SizedBox(
        width: SoliplexBreakpoints.tablet.toDouble(),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Headline(usage: usage),
              const SizedBox(height: SoliplexSpacing.s4),
              if (entries.isEmpty)
                Text(
                  'Nothing counted yet.',
                  style: theme.textTheme.bodyMedium,
                )
              else ...[
                SizedBox(
                  height: 180,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 44,
                      sections: [
                        for (final entry in entries)
                          PieChartSectionData(
                            value: entry.tokens.toDouble(),
                            color: entry.color,
                            radius: 34,
                            showTitle: false,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: SoliplexSpacing.s4),
                for (final entry in entries) _BreakdownRow(entry: entry),
              ],
              if (usage.isApproximate) ...[
                const SizedBox(height: SoliplexSpacing.s4),
                _Caveats(usage: usage),
              ],
            ],
          ),
        ),
      ),
      actions: [
        SoliplexButton.text(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  /// Wedges, largest first, skipping anything that contributes nothing.
  ///
  /// Colours come from the scheme's existing roles rather than a
  /// categorical ramp: the design system has no such token, and adding one
  /// is a decision of its own.
  List<_Entry> _entries(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    const labels = <SegmentKind, String>{
      SegmentKind.userText: 'Your messages',
      SegmentKind.assistantText: 'Assistant replies',
      SegmentKind.toolCallArguments: 'Tool calls',
      SegmentKind.toolResult: 'Tool results',
      SegmentKind.compactedCapsule: 'Cited evidence',
      SegmentKind.compactedReceipt: 'Dropped evidence',
      SegmentKind.overhead: 'Room overhead',
    };

    final colors = <SegmentKind, Color>{
      SegmentKind.userText: scheme.primary,
      SegmentKind.assistantText: scheme.secondary,
      SegmentKind.toolCallArguments: scheme.tertiary,
      SegmentKind.toolResult: scheme.primaryContainer,
      SegmentKind.compactedCapsule: scheme.tertiaryContainer,
      SegmentKind.compactedReceipt: scheme.surfaceContainerHighest,
      SegmentKind.overhead: scheme.secondaryContainer,
    };

    final entries = <_Entry>[
      for (final kind in labels.keys)
        if ((usage.byKind[kind] ?? 0) > 0)
          _Entry(
            label: labels[kind]!,
            tokens: usage.byKind[kind]!,
            color: colors[kind]!,
          ),
    ]..sort((a, b) => b.tokens.compareTo(a.tokens));

    return entries;
  }
}

class _Entry {
  const _Entry({
    required this.label,
    required this.tokens,
    required this.color,
  });

  final String label;
  final int tokens;
  final Color color;
}

class _Headline extends StatelessWidget {
  const _Headline({required this.usage});

  final ContextUsage usage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = usage.fractionUsed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${usage.isApproximate ? '~' : ''}${usage.tokens} tokens',
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: SoliplexSpacing.s1),
        Text(
          fraction == null
              ? 'This room has not declared a context window, so there is '
                  'no percentage to show.'
              : '${(fraction * 100).round()}% of '
                  '${usage.contextWindow} — '
                  '${usage.tokensRemaining} remaining',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.entry});

  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
      child: Row(
        children: [
          Container(
            width: SoliplexSpacing.s3,
            height: SoliplexSpacing.s3,
            decoration: BoxDecoration(
              color: entry.color,
              borderRadius: BorderRadius.circular(context.radii.sm),
            ),
          ),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: Text(entry.label, style: theme.textTheme.bodyMedium),
          ),
          Text(
            '${entry.tokens}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Says plainly why a number is approximate, rather than letting the user
/// wonder whether it can be trusted.
class _Caveats extends StatelessWidget {
  const _Caveats({required this.usage});

  final ContextUsage usage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final reasons = <String>[
      if (usage.isProvisional)
        'Still calibrating — this reads low until a few replies have '
            'completed.',
      if (!usage.isExact)
        'Estimated: no exact tokenizer is available for this model.',
      if (usage.hasUncountableContent)
        'This thread has attachments whose cost cannot be measured from '
            'text alone.',
    ];

    return Container(
      padding: const EdgeInsets.all(SoliplexSpacing.s3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(context.radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final reason in reasons)
            Padding(
              padding: const EdgeInsets.only(bottom: SoliplexSpacing.s1),
              child: Text(reason, style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}
