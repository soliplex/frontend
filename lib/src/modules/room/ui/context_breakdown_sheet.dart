import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;
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

/// Which slice of the window the chart is drawing.
enum ContextChartScope {
  /// The whole window, so the unused part is visible as its own wedge.
  full,

  /// Only what is occupied, so small categories are readable.
  used,
}

/// The breakdown behind the composer's context gauge.
class ContextBreakdownDialog extends StatefulWidget {
  /// Creates the dialog.
  const ContextBreakdownDialog({required this.usage, super.key});

  /// The reading to explain.
  final ContextUsage usage;

  @override
  State<ContextBreakdownDialog> createState() => _ContextBreakdownDialogState();
}

class _ContextBreakdownDialogState extends State<ContextBreakdownDialog> {
  /// Opens on the whole window, because the first question a gauge
  /// raises is "how much room is left" rather than "what is in there".
  ContextChartScope _scope = ContextChartScope.full;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usage = widget.usage;
    final entries = _entries(context);

    // Without a window there is no unused part to draw, so the choice
    // would be between one view and the same view.
    final canScope = usage.hasWindow && entries.isNotEmpty;
    final scope = canScope ? _scope : ContextChartScope.used;

    return AlertDialog(
      // The count is the title. A separate 'Context usage' heading sat
      // above it in a smaller style, which inverted the hierarchy — the
      // label was louder than the number it labelled — and said nothing
      // the gauge that opened this had not already said.
      title: Text(
        '${usage.isApproximate ? '~' : ''}${usage.tokens} tokens',
        style: theme.textTheme.headlineMedium,
      ),
      // A maximum, not a fixed width: a dialog pinned to the tablet
      // breakpoint overflows every screen narrower than one.
      content: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: SoliplexBreakpoints.tablet * 1.0,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Headline(
                usage: usage,
                scope: scope,
                onScopeChanged:
                    canScope ? (next) => setState(() => _scope = next) : null,
              ),
              const SizedBox(height: SoliplexSpacing.s4),
              if (entries.isEmpty)
                Text(
                  'Nothing counted yet.',
                  style: theme.textTheme.bodyMedium,
                )
              else ...[
                _Donut(usage: usage, entries: entries, scope: scope),
                const SizedBox(height: SoliplexSpacing.s4),
                _Legend(usage: usage, entries: entries, scope: scope),
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
  List<_Entry> _entries(BuildContext context) {
    const labels = <SegmentKind, String>{
      SegmentKind.userText: 'Your messages',
      SegmentKind.assistantText: 'Assistant replies',
      SegmentKind.toolCallArguments: 'Tool calls',
      SegmentKind.toolResult: 'Tool results',
      SegmentKind.compactedCapsule: 'Cited evidence',
      SegmentKind.compactedReceipt: 'Dropped evidence',
      SegmentKind.overhead: 'Room overhead',
    };

    final palette = categoricalColors(context);

    return <_Entry>[
      for (final kind in labels.keys)
        if ((widget.usage.byKind[kind] ?? 0) > 0)
          _Entry(
            label: labels[kind]!,
            tokens: widget.usage.byKind[kind]!,
            color: palette[kind]!,
          ),
    ]..sort((a, b) => b.tokens.compareTo(a.tokens));
  }
}

/// A colour per segment kind, drawn from the three symbolic hues.
///
/// The design system has no categorical ramp, and adding one is a
/// decision of its own, so these are derived from `info`, `success` and
/// `warning` — the only hues it defines that are neither a status
/// warning about the content nor a neutral.
///
/// The container tokens are deliberately *not* used, even though they
/// would be the obvious second tone. They are surfaces meant to sit
/// behind text: `infoContainer` is a near-white in the light theme and a
/// near-black in the dark one, so as wedges they would dissolve into the
/// background in whichever theme you happened to be looking at.
@visibleForTesting
Map<SegmentKind, Color> categoricalColors(BuildContext context) {
  final tone = _Tone(Theme.of(context).colorScheme);

  return {
    // The two that dominate an ordinary thread get the two most
    // distinct hues, so the shape of a conversation reads at a glance.
    SegmentKind.overhead: tone.of(context.info, _Depth.base),
    SegmentKind.userText: tone.of(context.success, _Depth.base),
    SegmentKind.assistantText: tone.of(context.success, _Depth.deep),
    SegmentKind.toolCallArguments: tone.of(context.warning, _Depth.base),
    SegmentKind.toolResult: tone.of(context.warning, _Depth.deep),
    SegmentKind.compactedCapsule: tone.of(context.info, _Depth.deep),
    // Neither compaction kind is reachable today: the backend reports
    // evidence as ordinary tool results. They are coloured anyway so a
    // future that does report them is not silently monochrome.
    SegmentKind.compactedReceipt: tone.of(context.warning, _Depth.soft),
  };
}

/// How far a tone is pushed away from the surface behind it.
///
/// These are contrast ratios, not lightness steps, because equal
/// lightness does not mean equal visibility: a fully saturated orange at
/// the same HSL lightness as a blue is roughly twice as luminous, so a
/// palette built on lightness alone leaves the warm hues washing out on
/// a white background. Solving for contrast puts every category on the
/// same footing whatever its hue.
///
/// The floor is 3.0, the WCAG 2.1 minimum for a graphical object that
/// carries meaning (1.4.11). A wedge nobody can pick out is a wedge that
/// says nothing.
/// The colour of the unused part of the window.
@visibleForTesting
Color freeSpaceColor(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return _Tone(scheme).free(scheme.outlineVariant);
}

enum _Depth {
  /// Furthest from the surface.
  deep(7.0),

  /// The middle step.
  base(4.8),

  /// Closest to the surface, still above the non-text minimum.
  soft(3.2);

  const _Depth(this.contrast);

  final double contrast;
}

/// Contrast for the unused part of the window.
///
/// Deliberately below the categories: it has to read as a distinct band
/// rather than as a hole in the ring, without competing with the wedges
/// that carry the actual information.
const _freeSpaceContrast = 2.1;

/// Derives tones that hold their contrast against the surface behind
/// them, in either theme.
///
/// Hue and saturation are left alone — shifting those would turn one
/// category's colour into another's — so lightness is the only thing
/// moved, and it is moved to wherever the requested contrast lands.
class _Tone {
  _Tone(ColorScheme scheme) : _surface = scheme.surface;

  final Color _surface;

  Color of(Color hue, _Depth depth) => _at(hue, depth.contrast);

  Color free(Color neutral) => _at(neutral, _freeSpaceContrast);

  /// The tone of [hue] whose contrast against the surface is [target].
  ///
  /// Contrast is monotonic in lightness on either side of the surface,
  /// so a bisection converges: on a light surface the search runs down
  /// towards black, on a dark one up towards white.
  Color _at(Color hue, double target) {
    final hsl = HSLColor.fromColor(hue);
    final towardsBlack = _surface.computeLuminance() > 0.5;

    // The full scale, not a range anchored at the hue's own lightness.
    // The dark theme's tokens already clear every target on their own,
    // so anchoring there left all three depths resolving to the same
    // point and the palette collapsed to one tone per hue.
    var lo = 0.0;
    var hi = 1.0;

    // A hue that cannot reach the target even at the extreme — a
    // saturated yellow on white, say — settles at the extreme, which is
    // the most contrast it has to give.
    for (var i = 0; i < 24; i++) {
      final mid = (lo + hi) / 2;
      final candidate = hsl.withLightness(mid).toColor();

      if (_contrast(candidate, _surface) > target) {
        if (towardsBlack) {
          lo = mid;
        } else {
          hi = mid;
        }
      } else if (towardsBlack) {
        hi = mid;
      } else {
        lo = mid;
      }
    }

    return hsl.withLightness((lo + hi) / 2).toColor();
  }
}

/// WCAG relative-luminance contrast ratio.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;

  return (lighter + 0.05) / (darker + 0.05);
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
  const _Headline({
    required this.usage,
    required this.scope,
    required this.onScopeChanged,
  });

  final ContextUsage usage;
  final ContextChartScope scope;
  final ValueChanged<ContextChartScope>? onScopeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = usage.fractionUsed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The summary and the control that reframes it belong on one
        // line: the toggle changes what the percentage is a percentage
        // of, so putting them apart would hide that connection.
        Row(
          children: [
            Expanded(
              child: Text(
                fraction == null
                    ? 'This room has not declared a context window, so '
                        'there is no percentage to show.'
                    : '${(fraction * 100).round()}% of '
                        '${usage.contextWindow} — '
                        '${usage.tokensRemaining} remaining',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (onScopeChanged case final onChanged?) ...[
              const SizedBox(width: SoliplexSpacing.s3),
              SegmentedButton<ContextChartScope>(
                segments: const [
                  ButtonSegment(
                    value: ContextChartScope.full,
                    label: Text('Window'),
                  ),
                  ButtonSegment(
                    value: ContextChartScope.used,
                    label: Text('Used'),
                  ),
                ],
                selected: {scope},
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onSelectionChanged: (selected) => onChanged(selected.first),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _Donut extends StatelessWidget {
  const _Donut({
    required this.usage,
    required this.entries,
    required this.scope,
  });

  final ContextUsage usage;
  final List<_Entry> entries;
  final ContextChartScope scope;

  @override
  Widget build(BuildContext context) {
    final free = _freeTokens();

    return SizedBox(
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
            if (free > 0)
              PieChartSectionData(
                value: free.toDouble(),
                // Not the surface: an unused wedge painted the colour
                // of the dialog behind it reads as a gap in the ring
                // rather than as room to spare.
                color: freeSpaceColor(context),
                radius: 34,
                showTitle: false,
              ),
          ],
        ),
      ),
    );
  }

  /// Unoccupied tokens, or zero when the chart is only showing what is
  /// occupied.
  int _freeTokens() {
    if (scope == ContextChartScope.used) return 0;
    return usage.tokensRemaining ?? 0;
  }
}

/// The key, laid out across the dialog rather than down it.
///
/// A column of one row per category pushed the caveats below the fold on
/// a short dialog; wrapping keeps the whole breakdown in view, and the
/// counts stay readable because each entry carries its own.
class _Legend extends StatelessWidget {
  const _Legend({
    required this.usage,
    required this.entries,
    required this.scope,
  });

  final ContextUsage usage;
  final List<_Entry> entries;
  final ContextChartScope scope;

  @override
  Widget build(BuildContext context) {
    final free =
        scope == ContextChartScope.full ? (usage.tokensRemaining ?? 0) : 0;

    return Wrap(
      spacing: SoliplexSpacing.s4,
      runSpacing: SoliplexSpacing.s2,
      children: [
        for (final entry in entries)
          _LegendItem(
            label: entry.label,
            tokens: entry.tokens,
            color: entry.color,
          ),
        if (free > 0)
          _LegendItem(
            label: 'Free',
            tokens: free,
            color: freeSpaceColor(context),
          ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.label,
    required this.tokens,
    required this.color,
  });

  final String label;
  final int tokens;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: SoliplexSpacing.s3,
          height: SoliplexSpacing.s3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(context.radii.sm),
          ),
        ),
        const SizedBox(width: SoliplexSpacing.s2),
        // A label longer than the line it lands on truncates rather
        // than overflowing the legend.
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: SoliplexSpacing.s1),
        Text(
          '$tokens',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
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
        'No reply has been measured yet, so this is what the room costs '
            'before the conversation is counted.',
      if (!usage.isExact)
        'Includes the message being composed, which is estimated — and '
            'rounded up, so the reading never runs low.',
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
