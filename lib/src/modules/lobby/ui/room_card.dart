import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';

class RoomCard extends StatelessWidget {
  const RoomCard({
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
    return Card(
      // The list owns the horizontal gutter; the card owns only the 12px
      // (s3) inter-row gap, matching the design mockup's list tiles.
      margin: const EdgeInsets.only(bottom: SoliplexSpacing.s3),
      child: ListTile(
        // Match RoomGridCard's title/subtitle styles so the two views read
        // identically: titleMedium name, small muted description.
        title: Text(room.name, style: theme.textTheme.titleMedium),
        subtitle: room.description.isNotEmpty
            ? Text(
                room.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : null,
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
}
