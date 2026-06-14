import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// A small primary-colored dot marking a room with unread activity.
///
/// A boolean affordance only — the lobby tracks *whether* a room has newer
/// activity than the user last saw, not how many messages. Shared by the
/// list ([RoomCard]) and grid ([RoomGridCard]) views so the marker reads
/// identically in both.
class UnreadDot extends StatelessWidget {
  const UnreadDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Unread activity',
      child: Container(
        width: SoliplexSpacing.s2,
        height: SoliplexSpacing.s2,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
