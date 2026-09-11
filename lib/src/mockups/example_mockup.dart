import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../core/app_identity.dart';

/// A starter mockup: the brand logo, one of each branded component, and a
/// layout that switches at the tablet breakpoint — enough to confirm the
/// harness carries the theme, and a template to copy from.
class ExampleMockup extends StatelessWidget {
  const ExampleMockup({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(SoliplexSpacing.s2),
          child: BrandLogo(identity: AppIdentity.soliplex),
        ),
        title: Text(AppIdentity.soliplex.appName),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= SoliplexBreakpoints.tablet;
          final cards = [
            _Card(
              title: 'Components',
              child: Wrap(
                spacing: SoliplexSpacing.s2,
                runSpacing: SoliplexSpacing.s2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SoliplexButton.filled(
                    onPressed: () {},
                    child: const Text('Primary'),
                  ),
                  SoliplexButton.outlined(
                    intent: ButtonIntent.danger,
                    onPressed: () {},
                    child: const Text('Delete'),
                  ),
                  const SoliplexBadge(
                    label: Text('Running'),
                    intent: BadgeIntent.info,
                    icon: Icon(Icons.play_arrow),
                  ),
                  SoliplexChip.filter(
                    label: const Text('Filter'),
                    selected: true,
                    onSelected: (_) {},
                  ),
                ],
              ),
            ),
            _Card(
              title: 'Input',
              child: const SoliplexInput(label: 'Room name'),
            ),
            _Card(
              title: 'Status colors',
              child: Row(
                children: [
                  for (final (label, color) in [
                    ('danger', context.danger),
                    ('success', context.success),
                    ('warning', context.warning),
                    ('info', context.info),
                  ])
                    Expanded(
                      child: Column(
                        children: [
                          Container(
                            height: SoliplexSpacing.s6,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius:
                                  BorderRadius.circular(context.radii.sm),
                            ),
                          ),
                          const SizedBox(height: SoliplexSpacing.s1),
                          Text(label, style: theme.textTheme.labelSmall),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ];
          return SingleChildScrollView(
            padding: const EdgeInsets.all(SoliplexSpacing.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isWide ? 'Wide layout (≥ tablet)' : 'Narrow layout',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: SoliplexSpacing.s4),
                if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final card in cards) ...[
                        Expanded(child: card),
                        if (card != cards.last)
                          const SizedBox(width: SoliplexSpacing.s4),
                      ],
                    ],
                  )
                else
                  for (final card in cards) ...[
                    card,
                    if (card != cards.last)
                      const SizedBox(height: SoliplexSpacing.s4),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(SoliplexSpacing.s4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(context.radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: SoliplexSpacing.s3),
          child,
        ],
      ),
    );
  }
}
