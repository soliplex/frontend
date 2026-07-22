import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../../../shared/relative_time.dart';
import 'room_markings_row.dart';
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
    // The marking + quiz indicator get their own row below the tile (see
    // RoomMarkingsRow); keeping them off the trailing edge leaves the room name
    // the full tile width instead of a few squeezed letters (issue #427). The
    // badge is always mounted as a seam, so on a stock build (no classification,
    // no quizzes) the row costs no layout and we skip its padding entirely.
    final showMarkings = roomHasVisibleMarkings(context, room);
    return Card(
      // The list owns the horizontal gutter; the card owns only the s3
      // inter-row gap, matching the design mockup's list tiles.
      margin: const EdgeInsets.only(bottom: SoliplexSpacing.s3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            // Mirror RoomGridCard's name row: the unread dot leads the name on
            // the title line, so it reads as a status of the room. It sits
            // inline (not in ListTile.leading, which centers vertically against
            // the whole tile and would drop the dot beside the description).
            // Conditional — no reserved gutter — so a read row keeps its full
            // name width; only unread rows indent.
            title: Row(
              children: [
                if (isUnread) ...[
                  const UnreadDot(),
                  const SizedBox(width: SoliplexSpacing.s2),
                ],
                // titleMedium name, matching RoomGridCard so the two views read
                // identically.
                Expanded(
                  child: Text(
                    room.name,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            subtitle: _buildSubtitle(theme),
            trailing: IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'Room info',
              onPressed: onInfoTap,
            ),
            onTap: onTap,
          ),
          if (showMarkings)
            Padding(
              // Align with the ListTile's content inset (s4) and leave an s3
              // gap to the card's bottom edge.
              padding: const EdgeInsets.fromLTRB(
                SoliplexSpacing.s4,
                0,
                SoliplexSpacing.s4,
                SoliplexSpacing.s3,
              ),
              child: RoomMarkingsRow(room: room),
            )
          else
            // Nothing to show, but keep the badge seam mounted (zero-size).
            RoomMarkingsRow(room: room),
        ],
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
