import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import '../../../../soliplex_frontend.dart';

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
    return Card(
      child: ListTile(
        title: Text(room.name),
        subtitle: room.description.isNotEmpty ? Text(room.description) : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (room.hasQuizzes)
              Tooltip(
                message: 'Has quizzes',
                child: Icon(
                  Icons.quiz,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: onInfoTap,
            ),
          ],
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: SoliplexSpacing.s2,
          vertical: SoliplexSpacing.s4,
        ),
        onTap: onTap,
      ),
    );
  }
}
