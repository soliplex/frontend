import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../../../shared/relative_time.dart';
import 'unread_dot.dart';

class RoomCard extends StatelessWidget {
  const RoomCard({
    super.key,
    required this.room,
    required this.onTap,
    required this.onInfoTap,
    this.activityTime,
    this.isUnread = false,
  });

  final Room room;
  final VoidCallback onTap;
  final VoidCallback onInfoTap;

  /// The room's last-activity time, shown as a muted relative label under the
  /// title. Null while unknown (not yet fetched, or the room has no activity).
  final DateTime? activityTime;

  /// Whether the room has activity newer than the user last saw, surfaced as
  /// a small dot. A boolean affordance only — there is no unread count.
  final bool isUnread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      // The list owns the horizontal gutter; the card owns only the s3
      // inter-row gap, matching the design mockup's list tiles.
      margin: const EdgeInsets.only(bottom: SoliplexSpacing.s3),
      child: ListTile(
        // Match RoomGridCard's title/subtitle styles so the two views read
        // identically: titleMedium name, small muted description.
        title: Text(
          room.name,
          style: theme.textTheme.titleMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: _buildSubtitle(theme),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isUnread) ...[
              const UnreadDot(),
              const SizedBox(width: SoliplexSpacing.s2),
            ],
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
        if (hasDescription)
          Text(
            room.description,
            style: muted,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        if (time != null) ...[
          if (hasDescription) const SizedBox(height: SoliplexSpacing.s1),
          // A small clock fronts the relative time so the row reads as
          // "last activity"; the tooltip names it for anyone who needs the
          // label spelled out.
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
