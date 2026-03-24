import 'package:flutter/material.dart';

import '../../auth/server_entry.dart';

class RoomScreen extends StatelessWidget {
  const RoomScreen({
    super.key,
    required this.serverEntry,
    required this.roomId,
    required this.threadId,
  });

  final ServerEntry serverEntry;
  final String roomId;
  final String? threadId;

  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}
