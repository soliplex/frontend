import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class RoomPlaceholderScreen extends StatelessWidget {
  const RoomPlaceholderScreen({
    super.key,
    required this.serverAlias,
    required this.roomId,
    this.serverId,
  });

  final String serverAlias;
  final String? serverId;
  final String roomId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Room: $roomId'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/lobby'),
        ),
      ),
      body: Center(
        child: Text(
          'Conversation UI — coming soon\n\n'
          'Server: ${serverId ?? serverAlias}\nRoom: $roomId',
        ),
      ),
    );
  }
}
