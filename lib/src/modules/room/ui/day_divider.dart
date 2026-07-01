import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// A centered calendar-day separator drawn between message groups on different
/// days (and above the first message). [label] comes from `formatDayDivider`
/// (e.g. `Today`, `Monday, June 23`); it is uppercased here as a style choice.
class DayDivider extends StatelessWidget {
  const DayDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: SoliplexSpacing.s4),
      child: Row(
        children: [
          Expanded(child: Divider(color: color)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s2),
            child: Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ),
          Expanded(child: Divider(color: color)),
        ],
      ),
    );
  }
}
