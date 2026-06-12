import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../../../shared/relative_time.dart';

class RoomCard extends StatelessWidget {
  const RoomCard({
    super.key,
    required this.room,
    required this.onTap,
    required this.onInfoTap,
    this.activityTime,
  });

  final Room room;
  final VoidCallback onTap;
  final VoidCallback onInfoTap;

  /// Most-recent-thread timestamp, shown as a muted relative label under the
  /// title. Null while unknown (not yet fetched, or the room has no threads).
  final DateTime? activityTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      // The list owns the horizontal gutter; the card owns only the 12px
      // (s3) inter-row gap, matching the design mockup's list tiles.
      margin: const EdgeInsets.only(bottom: SoliplexSpacing.s3),
      child: ListTile(
        // Match RoomGridCard's title/subtitle styles so the two views read
        // identically: titleMedium name, small muted description.
        title: Text(room.name, style: theme.textTheme.titleMedium),
        subtitle: _buildSubtitle(theme),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Leading marking; renders nothing until a deployment
            // configures classifications. Backend per-room value wires in
            // here later via `classification:`.
            const SoliplexClassificationBadge(),
            const SizedBox(width: SoliplexSpacing.s2),
            if (room.hasQuizzes)
              Tooltip(
                message: 'Has quizzes',
                child: Icon(
                  Icons.quiz,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              ),
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: onInfoTap,
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  /// Description and/or the relative activity time, stacked left-aligned below
  /// the title (so the time reads at the row's bottom-left, opposite the
  /// trailing info button). Null when there is neither.
  Widget? _buildSubtitle(ThemeData theme) {
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final hasDescription = room.description.isNotEmpty;
    final time = activityTime;
    if (!hasDescription && time == null) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasDescription) Text(room.description, style: muted),
        if (time != null) ...[
          if (hasDescription) const SizedBox(height: SoliplexSpacing.s1),
          // A small clock fronts the relative time so the row reads as
          // "last activity" without spelling it out on every card; the
          // tooltip carries the full meaning for anyone who needs it.
          Tooltip(
            message: 'Last activity',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.schedule,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: SoliplexSpacing.s1),
                Text(formatRelativeTime(time), style: muted),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
