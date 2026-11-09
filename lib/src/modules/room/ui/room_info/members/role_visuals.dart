import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'room_access.dart';

/// How a role looks wherever it appears, so the card, its menu, the dialogs and
/// the filters agree.
///
/// The tint climbs with what the role can do: neutral reads, info writes,
/// warning administers. Green stays free for a room's healthy state, and the
/// label palette stays out entirely, so a role never reads as a thread label.
extension RoleVisuals on RoomRole {
  IconData get icon => switch (this) {
        RoomRole.reader => Icons.visibility_outlined,
        RoomRole.member => Icons.edit_outlined,
        RoomRole.admin => Icons.manage_accounts_outlined,
      };

  BadgeIntent get badgeIntent => switch (this) {
        RoomRole.reader => BadgeIntent.neutral,
        RoomRole.member => BadgeIntent.info,
        RoomRole.admin => BadgeIntent.warning,
      };

  ChipIntent get chipIntent => switch (this) {
        RoomRole.reader => ChipIntent.neutral,
        RoomRole.member => ChipIntent.info,
        RoomRole.admin => ChipIntent.warning,
      };
}

class RoleBadge extends StatelessWidget {
  const RoleBadge(this.role, {super.key});

  final RoomRole role;

  @override
  Widget build(BuildContext context) => SoliplexBadge(
        label: Text(role.label),
        icon: Icon(role.icon),
        intent: role.badgeIntent,
      );
}
