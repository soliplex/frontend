import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../../../shared/relative_time.dart';
import 'room_markings_row.dart';
import 'unread_dot.dart';

/// Vertical card used for the lobby's grid layout: open on tap, info
/// button, and a quiz indicator, in a shape that tiles cleanly into a
/// grid cell. The list-row counterpart is [RoomCard].
class RoomGridCard extends StatelessWidget {
  const RoomGridCard({
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

  /// The room's last-activity time, shown as a muted relative label in the
  /// footer's bottom-left. Null while unknown (not yet fetched, or no activity).
  final DateTime? activityTime;

  /// Whether the room has activity newer than the user last saw, surfaced as
  /// a small dot beside the name. A boolean affordance only — no count.
  final bool isUnread;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(context.radii.md);
    // Marking + quiz live on their own row (see RoomMarkingsRow) so the room
    // name owns the full title row. The badge is always mounted as a seam; only
    // spend a dedicated row's gap once there's actually a marking or quiz.
    final showMarkings = roomHasVisibleMarkings(context, room);
    return Card(
      // The grid owns all spacing (s3 gaps between cells and rows); drop the
      // default card margin so each card fills its cell cleanly.
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.all(SoliplexSpacing.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            // Fill the cell height the grid hands us so a row of cards reads
            // as a regular block; the footer is then pinned to the bottom via
            // the Spacer below. The grid (or any host) must give this card a
            // bounded height — see _RoomGrid in lobby_screen.dart.
            mainAxisSize: MainAxisSize.max,
            children: [
              Row(
                children: [
                  if (isUnread) ...[
                    const UnreadDot(),
                    const SizedBox(width: SoliplexSpacing.s2),
                  ],
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
              if (room.description.isNotEmpty) ...[
                const SizedBox(height: SoliplexSpacing.s2),
                Text(
                  room.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              // Minimum gap above the bottom cluster, then a Spacer so it sits
              // at the bottom of a taller-than-content card.
              const SizedBox(height: SoliplexSpacing.s2),
              const Spacer(),
              // Dedicated marking + quiz row, kept off the title row. Always
              // mounts the badge seam; the gap below is only spent when the
              // row actually shows something.
              RoomMarkingsRow(room: room),
              if (showMarkings) const SizedBox(height: SoliplexSpacing.s2),
              Row(
                children: [
                  // Bottom-left: relative activity time when known.
                  Expanded(
                    child: activityTime == null
                        ? const SizedBox.shrink()
                        : Tooltip(
                            // Clock-fronted relative time; the tooltip names
                            // it so the label needn't crowd the compact card.
                            message: 'Last activity',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.schedule,
                                  size: 14,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: SoliplexSpacing.s1),
                                Flexible(
                                  child: Text(
                                    formatRelativeTime(activityTime!),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.info_outline),
                    tooltip: 'Room info',
                    onPressed: onInfoTap,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
