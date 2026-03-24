import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

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
        trailing: IconButton(
          icon: const Icon(Icons.info_outline),
          onPressed: onInfoTap,
        ),
        onTap: onTap,
      ),
    );
  }
}
