import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// Vertical card used for the lobby's grid layout: open on tap, info
/// button, and a quiz indicator, in a shape that tiles cleanly into a
/// grid cell. The list-row counterpart is [RoomCard].
class RoomGridCard extends StatelessWidget {
  const RoomGridCard({
    super.key,
    required this.room,
    required this.onTap,
    required this.onInfoTap,
  });

  final Room room;
  final VoidCallback onTap;
  final VoidCallback onInfoTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(soliplexRadii.md);
    return Card(
      // The grid's Wrap owns all spacing (s3 run/cross gaps); drop the
      // default card margin so each card fills its cell cleanly.
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.all(SoliplexSpacing.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
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
              const SizedBox(height: SoliplexSpacing.s2),
              Row(
                children: [
                  // Bottom-left marking; renders nothing until a deployment
                  // configures classifications. Backend per-room value
                  // wires in here later via `classification:`.
                  const SoliplexClassificationBadge(),
                  const Spacer(),
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
