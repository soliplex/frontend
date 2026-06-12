import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../../../shared/relative_time.dart';

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
  });

  final Room room;
  final VoidCallback onTap;
  final VoidCallback onInfoTap;

  /// Most-recent-thread timestamp, shown as a muted relative label in the
  /// footer's bottom-left. Null while unknown (not yet fetched, or no threads).
  final DateTime? activityTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(soliplexRadii.md);
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
                  Expanded(
                    child: Text(
                      room.name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (room.hasQuizzes)
                    Tooltip(
                      message: 'Has quizzes',
                      child: Icon(
                        Icons.quiz,
                        size: 20,
                        color: theme.colorScheme.primary,
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
              // Minimum gap above the footer, then a Spacer so the footer
              // sits at the bottom of a taller-than-content card.
              const SizedBox(height: SoliplexSpacing.s2),
              const Spacer(),
              Row(
                children: [
                  // Bottom-left: relative activity time when known, then the
                  // marking (which renders nothing until a deployment
                  // configures classifications — backend per-room value wires
                  // in here later via `classification:`).
                  Expanded(
                    child: activityTime == null
                        ? const SizedBox.shrink()
                        : Tooltip(
                            // Clock-fronted relative time; the tooltip names it
                            // so the cards don't repeat "Last activity" inline.
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
                  const SoliplexClassificationBadge(),
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
