import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../context_gauge.dart';
import '../context_usage.dart';
import 'panel_state.dart';

/// Everything that shapes what the model sees on the next request, in three
/// collapsible segments. Databases open by default: it is the one people
/// change most, and the reason the panel exists.
///
/// An accordion whose segments do not share space evenly — each has its own
/// claim on the panel's height, honoured in this order by [_AccordionLayout]:
///
/// 1. every segment header, and the skills segment's switch and loaded chips,
///    are fixed — they are never scrolled away;
/// 2. the context usage body takes all the height it needs, and scrolls
///    only when the whole panel cannot hold it;
/// 3. the advanced-skills list shrinks and scrolls, keeping at most half of
///    what is left while the database list is open too;
/// 4. the database list takes whatever remains — it is only a list, so it
///    is the one that flexes, in both directions.
class ContextTab extends StatelessWidget {
  const ContextTab({required this.state, super.key});

  final ThreadPanelState state;

  @override
  Widget build(BuildContext context) {
    final databases = state.databases;
    final advanced = state.advancedSkills;
    final usage = state.contextUsage;
    final databasesOpen = state.isSegmentOpen('databases');
    final skillsOpen = state.isSegmentOpen('skills');
    final usageOpen = state.isSegmentOpen('usage');

    // In visual order. The delegate reads the claim off each slot's kind.
    final slots = <_Slot>[
      _Slot(
        'databases.header',
        _Claim.fixed,
        _SegmentHeader(
          icon: Icons.storage,
          title: 'Databases',
          summary: '${state.connectedDatabaseCount} of '
              '${databases.length} connected',
          open: databasesOpen,
          onTap: () => state.toggleSegment('databases'),
        ),
      ),
      if (databasesOpen) ...[
        _Slot(
          'databases.list',
          _Claim.remainder,
          ListView.builder(
            controller: state.scrollFor('databases'),
            itemCount: databases.length,
            itemBuilder: (context, i) {
              final db = databases[i];
              return _DatabaseRow(
                db: db,
                expanded: state.isRowExpanded(db.id),
                onExpand: () => state.toggleRow(db.id),
                onToggle: () => state.toggleDatabase(db.id),
              );
            },
          ),
        ),
        const _Slot('databases.end', _Claim.fixed, Divider(height: 1)),
      ],
      _Slot(
        'skills.header',
        _Claim.fixed,
        _SegmentHeader(
          icon: Icons.extension_outlined,
          title: 'Skills',
          summary: '${state.loadedSkills.length} loaded',
          open: skillsOpen,
          onTap: () => state.toggleSegment('skills'),
        ),
      ),
      if (skillsOpen) ...[
        _Slot('skills.preamble', _Claim.fixed, _SkillsPreamble(state: state)),
        _Slot(
          'skills.list',
          _Claim.shrinking,
          ListView(
            controller: state.scrollFor('skills'),
            shrinkWrap: true,
            children: [
              for (final skill in advanced)
                _SkillRow(
                  skill: skill,
                  expanded: state.isRowExpanded(skill.id),
                  onExpand: () => state.toggleRow(skill.id),
                  onToggle: () => state.toggleSkill(skill.id),
                ),
            ],
          ),
        ),
        const _Slot('skills.end', _Claim.fixed, Divider(height: 1)),
      ],
      _Slot(
        'usage.header',
        _Claim.fixed,
        _SegmentHeader(
          icon: Icons.donut_large,
          title: 'Context usage',
          summary: usage.fractionUsed == null
              ? '${_thousands(usage.tokens)} tokens'
              : '${(usage.fractionUsed! * 100).round()}%',
          open: usageOpen,
          onTap: () => state.toggleSegment('usage'),
        ),
      ),
      if (usageOpen)
        _Slot(
          'usage.body',
          _Claim.needed,
          SingleChildScrollView(
            controller: state.scrollFor('usage'),
            child: _UsageSection(state: state),
          ),
        ),
    ];

    return CustomMultiChildLayout(
      delegate: _AccordionLayout(slots),
      children: [
        for (final slot in slots) LayoutId(id: slot.id, child: slot.child),
      ],
    );
  }
}

/// How a segment part claims height. See [ContextTab].
enum _Claim {
  /// Laid out at its own height; never scrolled away.
  fixed,

  /// All the height it needs, scrolling only when the panel cannot hold it.
  needed,

  /// Sized to content, but capped so it shrinks and scrolls under pressure.
  shrinking,

  /// Whatever is left.
  remainder,
}

class _Slot {
  const _Slot(this.id, this.claim, this.child);

  final String id;
  final _Claim claim;
  final Widget child;
}

/// Allocates the panel's height to the segment parts in claim order — fixed
/// parts first, then the one that takes what it needs, then the one that
/// shrinks, and the remainder to the list — and stacks them top to bottom.
class _AccordionLayout extends MultiChildLayoutDelegate {
  _AccordionLayout(this.slots);

  final List<_Slot> slots;

  @override
  void performLayout(Size size) {
    final heights = <String, double>{};
    final width = BoxConstraints(minWidth: size.width, maxWidth: size.width);
    double lay(_Slot slot, BoxConstraints constraints) =>
        heights[slot.id] = layoutChild(slot.id, constraints).height;

    var remaining = size.height;
    for (final slot in slots.where((s) => s.claim == _Claim.fixed)) {
      remaining -= lay(slot, width);
    }
    remaining = math.max(0, remaining);

    for (final slot in slots.where((s) => s.claim == _Claim.needed)) {
      remaining -= lay(slot, width.copyWith(maxHeight: remaining));
    }

    final hasRemainder = slots.any((s) => s.claim == _Claim.remainder);
    for (final slot in slots.where((s) => s.claim == _Claim.shrinking)) {
      final cap = hasRemainder ? remaining / 2 : remaining;
      remaining -= lay(slot, width.copyWith(maxHeight: cap));
    }

    for (final slot in slots.where((s) => s.claim == _Claim.remainder)) {
      lay(slot, width.copyWith(minHeight: remaining, maxHeight: remaining));
      remaining = 0;
    }

    var y = 0.0;
    for (final slot in slots) {
      positionChild(slot.id, Offset(0, y));
      y += heights[slot.id]!;
    }
  }

  @override
  bool shouldRelayout(_AccordionLayout old) =>
      old.slots.length != slots.length ||
      // Same ids, same claims — a rebuilt child with the same id still
      // relayouts through the framework's own dirty tracking.
      Iterable.generate(slots.length).any(
        (i) =>
            old.slots[i].id != slots[i].id ||
            old.slots[i].claim != slots[i].claim,
      );
}

/// A segment's title row: icon, name, a one-line summary that stays useful
/// while the segment is closed, and the chevron.
class _SegmentHeader extends StatelessWidget {
  const _SegmentHeader({
    required this.icon,
    required this.title,
    required this.summary,
    required this.open,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String summary;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SoliplexSpacing.s4,
          vertical: SoliplexSpacing.s3,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: SoliplexSpacing.s3),
            Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
            Text(
              summary,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: SoliplexSpacing.s2),
            Icon(
              open ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: scheme.outline,
            ),
          ],
        ),
      ),
    );
  }
}

/// A row that opens to a description: the shared shape of database and skill
/// rows. No leading icon — the segment header already carries one; status is
/// a dot in the meta line, and the action shows on hover (or while the row
/// is expanded, which is how touch reaches it).
class _ExpandableRow extends StatefulWidget {
  const _ExpandableRow({
    required this.title,
    required this.meta,
    required this.action,
    required this.description,
    required this.expanded,
    required this.onExpand,
  });

  final String title;

  /// Under the title: the status dot, a document count, a token cost.
  final Widget meta;
  final Widget action;
  final String description;
  final bool expanded;
  final VoidCallback onExpand;

  @override
  State<_ExpandableRow> createState() => _ExpandableRowState();
}

class _ExpandableRowState extends State<_ExpandableRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showAction = _hovered || widget.expanded;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Column(
        children: [
          InkWell(
            onTap: widget.onExpand,
            child: Padding(
              padding: const EdgeInsets.only(
                left: SoliplexSpacing.s6,
                right: SoliplexSpacing.s3,
                top: SoliplexSpacing.s3,
                bottom: SoliplexSpacing.s3,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: theme.textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: SoliplexSpacing.s2),
                        widget.meta,
                      ],
                    ),
                  ),
                  const SizedBox(width: SoliplexSpacing.s3),
                  // Keeps its footprint while hidden so the row does not
                  // shift as the pointer crosses it.
                  AnimatedOpacity(
                    opacity: showAction ? 1 : 0,
                    duration: const Duration(milliseconds: 120),
                    child: IgnorePointer(
                      ignoring: !showAction,
                      child: widget.action,
                    ),
                  ),
                  const SizedBox(width: SoliplexSpacing.s1),
                  Icon(
                    widget.expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
          if (widget.expanded)
            Padding(
              padding: const EdgeInsets.only(
                left: SoliplexSpacing.s6,
                right: SoliplexSpacing.s6,
                bottom: SoliplexSpacing.s4,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Status as a dot: filled in a symbolic colour for a state worth noticing,
/// hollow for the resting state, a spinner while in transit. The name of the
/// state lives in the tooltip.
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.label, this.color, this.busy = false});

  final String label;

  /// Null draws the hollow resting dot.
  final Color? color;
  final bool busy;

  static const _size = 8.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget dot;
    if (busy) {
      dot = SizedBox.square(
        dimension: _size + 2,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: color ?? scheme.onSurfaceVariant,
        ),
      );
    } else {
      dot = Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: color == null ? Border.all(color: scheme.outline) : null,
        ),
      );
    }
    return Tooltip(
      message: label,
      child: Padding(
        // Centres the dot on the meta line's text.
        padding: const EdgeInsets.only(right: SoliplexSpacing.s2),
        child: dot,
      ),
    );
  }
}

class _DatabaseRow extends StatelessWidget {
  const _DatabaseRow({
    required this.db,
    required this.expanded,
    required this.onExpand,
    required this.onToggle,
  });

  final RagDatabase db;
  final bool expanded;
  final VoidCallback onExpand;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color, busy) = switch (db.status) {
      DbStatus.connected => ('Connected', context.success, false),
      DbStatus.connecting => ('Connecting', context.info, true),
      DbStatus.indexing => ('Indexing', context.warning, false),
      DbStatus.unavailable => ('Unavailable', context.danger, false),
      DbStatus.available => ('Available', null, false),
    };
    final canToggle =
        db.status == DbStatus.available || db.status == DbStatus.connected;
    return _ExpandableRow(
      title: db.name,
      meta: Row(
        children: [
          _StatusDot(label: label, color: color, busy: busy),
          Flexible(
            child: Text(
              '${_thousands(db.documentCount)} docs',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      action: SoliplexButton.text(
        isCompact: true,
        isLoading: db.status == DbStatus.connecting,
        onPressed: canToggle ? onToggle : null,
        child: Text(
          db.status == DbStatus.connected ? 'Disconnect' : 'Connect',
        ),
      ),
      description: db.description,
      expanded: expanded,
      onExpand: onExpand,
    );
  }
}

/// Above the advanced list: the auto-load switch and what is loaded now.
class _SkillsPreamble extends StatelessWidget {
  const _SkillsPreamble({required this.state});

  final ThreadPanelState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final loaded = state.loadedSkills;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SoliplexSpacing.s6,
        SoliplexSpacing.s1,
        SoliplexSpacing.s6,
        SoliplexSpacing.s2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Auto-load basic skills',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: SoliplexSpacing.s1),
                    Text(
                      'Citing, tables, acronyms — on every request',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: SoliplexSpacing.s3),
              Switch(
                value: state.autoLoadBasicSkills,
                onChanged: state.setAutoLoadBasicSkills,
              ),
            ],
          ),
          const SizedBox(height: SoliplexSpacing.s4),
          Text(
            loaded.isEmpty
                ? 'Nothing in context — the agent answers with no skills.'
                : 'In context now',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          if (loaded.isNotEmpty) ...[
            const SizedBox(height: SoliplexSpacing.s2),
            // One row, scrolling sideways: the list is a glance, not a
            // catalogue, and a wrap would push the advanced list down.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (i, skill) in loaded.indexed) ...[
                    if (i > 0) const SizedBox(width: SoliplexSpacing.s2),
                    SoliplexChip(
                      label: Text(skill.name),
                      // Basic skills ride the switch; only a hand-loaded one
                      // can be dropped from here.
                      onDeleted: skill.tier == SkillTier.advanced
                          ? () => state.toggleSkill(skill.id)
                          : null,
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: SoliplexSpacing.s6),
          Text(
            'Advanced — loaded by hand, each costs context',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}

class _SkillRow extends StatelessWidget {
  const _SkillRow({
    required this.skill,
    required this.expanded,
    required this.onExpand,
    required this.onToggle,
  });

  final AgentSkill skill;
  final bool expanded;
  final VoidCallback onExpand;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = skill.status == SkillStatus.loaded;
    final (label, color, busy) = switch (skill.status) {
      SkillStatus.loaded => ('Loaded', context.success, false),
      SkillStatus.loading => ('Loading', context.info, true),
      SkillStatus.unloaded => ('Not loaded', null, false),
    };
    return _ExpandableRow(
      title: skill.name,
      meta: Row(
        children: [
          _StatusDot(label: label, color: color, busy: busy),
          Flexible(
            child: Text(
              '~${_thousands(skill.tokens)} tokens',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      action: SoliplexButton.text(
        isCompact: true,
        isLoading: skill.status == SkillStatus.loading,
        onPressed: onToggle,
        child: Text(loaded ? 'Unload' : 'Load'),
      ),
      description: skill.description,
      expanded: expanded,
      onExpand: onExpand,
    );
  }
}

/// The ring with its numbers, and the handoff generator under it.
class _UsageSection extends StatelessWidget {
  const _UsageSection({required this.state});

  final ThreadPanelState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final usage = state.contextUsage;
    final window = usage.contextWindow;
    final remaining = usage.tokensRemaining;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SoliplexSpacing.s6,
        SoliplexSpacing.s2,
        SoliplexSpacing.s6,
        SoliplexSpacing.s6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ContextRing(usage: usage),
              const SizedBox(width: SoliplexSpacing.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      window == null
                          ? '${_thousands(usage.tokens)} tokens'
                          : '${_thousands(usage.tokens)} of '
                              '${_thousands(window)} tokens',
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (remaining != null)
                      Text(
                        '${_thousands(remaining)} remaining',
                        style:
                            theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    if (usage.isApproximate)
                      Text(
                        'Includes an estimate for the unsent draft',
                        style:
                            theme.textTheme.bodySmall?.copyWith(color: muted),
                      ),
                    const SizedBox(height: SoliplexSpacing.s3),
                    _ShareLegend(usage: usage),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: SoliplexSpacing.s6),
          switch (state.handoffStatus) {
            HandoffStatus.idle || HandoffStatus.generating => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Running out of room? Hand the thread off to a fresh one.',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  const SizedBox(height: SoliplexSpacing.s3),
                  SoliplexButton.outlined(
                    icon: const Icon(Icons.summarize_outlined),
                    isLoading: state.handoffStatus == HandoffStatus.generating,
                    onPressed: state.generateHandoff,
                    child: const Text('Generate handoff'),
                  ),
                ],
              ),
            HandoffStatus.ready => _HandoffBox(
                text: state.handoffText ?? '',
                onRegenerate: state.generateHandoff,
                onClose: state.clearHandoff,
              ),
          },
        ],
      ),
    );
  }
}

/// One line per share: swatch, name, tokens, and the share of the window
/// (or of the count, without a window). Largest first.
class _ShareLegend extends StatelessWidget {
  const _ShareLegend({required this.usage});

  final ContextUsage usage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final palette = contextShareColors(context);
    final denominator = usage.contextWindow ?? usage.tokens;
    final entries = [
      for (final share in ContextShare.values)
        if ((usage.byShare[share] ?? 0) > 0) (share, usage.byShare[share]!),
    ]..sort((a, b) => b.$2.compareTo(a.$2));

    return Column(
      children: [
        for (final (share, tokens) in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
            child: Row(
              children: [
                Container(
                  width: SoliplexSpacing.s2,
                  height: SoliplexSpacing.s2,
                  decoration: BoxDecoration(
                    color: palette[share],
                    borderRadius: BorderRadius.circular(context.radii.sm),
                  ),
                ),
                const SizedBox(width: SoliplexSpacing.s2),
                Expanded(
                  child: Text(
                    share.label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Text(
                  denominator > 0
                      ? '${_thousands(tokens)} · '
                          '${(tokens / denominator * 100).round()}%'
                      : _thousands(tokens),
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _HandoffBox extends StatelessWidget {
  const _HandoffBox({
    required this.text,
    required this.onRegenerate,
    required this.onClose,
  });

  final String text;
  final VoidCallback onRegenerate;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(context.radii.md),
      ),
      padding: const EdgeInsets.fromLTRB(
        SoliplexSpacing.s3,
        SoliplexSpacing.s2,
        SoliplexSpacing.s2,
        SoliplexSpacing.s3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Handoff', style: theme.textTheme.titleSmall),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Copy',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Handoff copied')),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Regenerate',
                visualDensity: VisualDensity.compact,
                onPressed: onRegenerate,
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Discard',
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
              ),
            ],
          ),
          SelectableText(
            text,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}

/// `41200` → `41,200`.
String _thousands(int n) {
  final s = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}
