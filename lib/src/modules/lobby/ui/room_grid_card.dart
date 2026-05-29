import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// Vertical card used for the lobby's grid layout. Carries the same
/// affordances as the list-row [RoomCard] (open on tap, info button,
/// quiz indicator) in a shape that tiles cleanly into a grid cell.
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
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: 'Room info',
                  onPressed: onInfoTap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
