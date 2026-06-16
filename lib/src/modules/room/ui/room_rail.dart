import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_client/soliplex_client.dart' show Room;
import 'package:soliplex_design/soliplex_design.dart';

import '../../auth/auth_tokens.dart';
import '../../auth/server_entry.dart';
import '../../lobby/ui/unread_dot.dart';

/// A signed-in identity for the rail's account menu: a display [name] and an
/// optional [email]. Resolved by the room screen from `/api/user_info`.
typedef RoomAccount = ({String name, String? email});

/// The compact, always-visible rail of rooms for the current server.
///
/// Discord-style: each room is a small initial avatar tinted by a hash of its
/// name (see [roomAvatarColor]); the selected room is marked with a leading
/// bar. The footer is a single ⋮ menu folding the account identity and the
/// developer utilities (Network Inspector, Versions) — there's no room beside
/// it for an account block at this width, so the identity lives inside the
/// menu. Creating a room is deferred; this only lists.
class RoomRail extends StatelessWidget {
  const RoomRail({
    super.key,
    required this.rooms,
    required this.selectedRoomId,
    required this.onSelectRoom,
    required this.entry,
    required this.account,
    required this.onNetworkInspector,
    required this.onVersions,
    this.roomsError,
    this.onRetryRooms,
    this.unreadRoomIds = const {},
  });

  /// The server's rooms, or `null` while loading.
  final List<Room>? rooms;

  /// Ids of rooms with activity newer than the user last saw — each gets an
  /// [UnreadDot]. Shares the lobby's per-device read model, so a room read in
  /// the lobby reads here too (and vice versa). Empty when stats are
  /// unavailable (e.g. a pre-stats backend), which simply shows no dots.
  final Set<String> unreadRoomIds;

  /// Non-null when the room list failed to load.
  final Object? roomsError;
  final VoidCallback? onRetryRooms;

  final String selectedRoomId;
  final void Function(String roomId) onSelectRoom;

  /// The current server entry; its session drives the Guest/signed-in label.
  final ServerEntry entry;

  /// The resolved profile for [entry], or `null` when unknown (best-effort
  /// fetch). Falls back to a generic "Signed in" / "Guest" label.
  final RoomAccount? account;

  final VoidCallback onNetworkInspector;
  final VoidCallback onVersions;

  /// Fixed rail width — wide enough for a 44px avatar plus the selection bar
  /// and breathing room, narrow enough to stay a rail.
  static const double width = 72;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: _buildList(context)),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s2),
          child: _RailAccountMenu(
            entry: entry,
            account: account,
            onNetworkInspector: onNetworkInspector,
            onVersions: onVersions,
          ),
        ),
      ],
    );
  }

  Widget _buildList(BuildContext context) {
    final rooms = this.rooms;
    if (roomsError != null) {
      return _RailMessage(
        icon: Icons.error_outline,
        tooltip: 'Failed to load rooms',
        onTap: onRetryRooms,
        color: Theme.of(context).colorScheme.error,
      );
    }
    if (rooms == null) {
      return const Center(
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s2),
      itemCount: rooms.length,
      itemBuilder: (context, index) {
        final room = rooms[index];
        return _RoomAvatarTile(
          room: room,
          selected: room.id == selectedRoomId,
          unread: unreadRoomIds.contains(room.id),
          onTap: () => onSelectRoom(room.id),
        );
      },
    );
  }
}

/// One room in the rail: an initial avatar tinted by [roomAvatarColor], with a
/// leading selection bar when selected and the room name in a tooltip.
class _RoomAvatarTile extends StatelessWidget {
  const _RoomAvatarTile({
    required this.room,
    required this.selected,
    required this.unread,
    required this.onTap,
  });

  final Room room;
  final bool selected;
  final bool unread;
  final VoidCallback onTap;

  static const double _avatar = 44;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = roomAvatarColor(room.name, theme.brightness);
    final fg = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
        ? Colors.white
        : Colors.black;

    return Tooltip(
      message: room.name,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
        child: SizedBox(
          height: _avatar,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Leading selection bar, hugging the rail's left edge.
              if (selected)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: SoliplexSpacing.s1,
                    height: _avatar - SoliplexSpacing.s2,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(soliplexRadii.sm),
                    ),
                  ),
                ),
              // Fixed-size box so the unread badge anchors to the avatar's
              // corner rather than the wider rail column.
              SizedBox.square(
                dimension: _avatar,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: Material(
                        color: bg,
                        // A selected avatar squares off (smaller radius) so the
                        // shape shift reinforces the leading bar.
                        borderRadius: BorderRadius.circular(
                            selected ? soliplexRadii.md : _avatar / 2),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: onTap,
                          child: Center(
                            child: Text(
                              _initial(room.name),
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(color: fg),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (unread)
                      const Positioned(top: 0, right: 0, child: _UnreadBadge()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _initial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.characters.first.toUpperCase();
  }
}

/// The shared [UnreadDot] ringed by a surface-colored circle so the marker
/// stays legible where it overlaps the colored avatar at its corner. The
/// 12px ring around the 8px dot yields an even 2px border on the scale.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: SoliplexSpacing.s3,
      height: SoliplexSpacing.s3,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        shape: BoxShape.circle,
      ),
      child: const UnreadDot(),
    );
  }
}

/// A centered status glyph for the rail body (loading-failed / retry).
class _RailMessage extends StatelessWidget {
  const _RailMessage({
    required this.icon,
    required this.tooltip,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: IconButton(
        icon: Icon(icon, color: color),
        tooltip: tooltip,
        onPressed: onTap,
      ),
    );
  }
}

/// The actions folded behind the rail's footer ⋮ menu. Account identity is a
/// non-interactive header above these.
enum _RailMenuAction { networkInspector, versions }

/// The rail footer: a single ⋮ that opens the account identity (as a header)
/// plus the developer utilities. The identity folds inside the menu since the
/// rail is too narrow for a block beside the button.
class _RailAccountMenu extends StatelessWidget {
  const _RailAccountMenu({
    required this.entry,
    required this.account,
    required this.onNetworkInspector,
    required this.onVersions,
  });

  final ServerEntry entry;
  final RoomAccount? account;
  final VoidCallback onNetworkInspector;
  final VoidCallback onVersions;

  void _onSelected(_RailMenuAction action) {
    switch (action) {
      case _RailMenuAction.networkInspector:
        onNetworkInspector();
      case _RailMenuAction.versions:
        onVersions();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Session is a per-entry signal; Watch refreshes the identity label on
    // sign-in / expiry without a parent rebuild.
    return Watch((context) {
      final identity = _resolveIdentity();
      return PopupMenuButton<_RailMenuAction>(
        icon: const Icon(Icons.more_vert),
        tooltip: 'Account & more',
        onSelected: _onSelected,
        itemBuilder: (context) => [
          PopupMenuItem<_RailMenuAction>(
            enabled: false,
            child: _AccountHeader(name: identity.name, email: identity.email),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: _RailMenuAction.networkInspector,
            child:
                _MenuRow(icon: Icons.lan_outlined, label: 'Network Inspector'),
          ),
          const PopupMenuItem(
            value: _RailMenuAction.versions,
            child: _MenuRow(icon: Icons.info_outline, label: 'Versions'),
          ),
        ],
      );
    });
  }

  RoomAccount _resolveIdentity() {
    final isAuthenticated =
        entry.requiresAuth && entry.auth.session.value is ActiveSession;
    if (!isAuthenticated) return (name: 'Guest', email: null);
    return account ?? (name: 'Signed in', email: null);
  }
}

/// The account identity shown at the top of the rail's ⋮ menu: an initial
/// avatar, the display name, and an optional email.
class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.name, required this.email});

  final String name;
  final String? email;

  static const double _avatar = 36;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _avatar,
          height: _avatar,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(soliplexRadii.sm),
          ),
          child: Text(
            name.characters.first.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: SoliplexSpacing.s3),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: theme.textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (email != null)
                Text(
                  email!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// An icon + label row for a ⋮ menu item.
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: SoliplexSpacing.s3),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

/// A deterministic, theme-aware accent color for a room's avatar, derived from
/// a stable hash of its [name] so the same room always gets the same hue.
///
/// Uses HSL rather than a literal swatch table: a fixed hex palette would be a
/// hex-literal violation outside the design package, and a hue wheel gives far
/// more distinct, evenly-spread colors. Saturation/lightness are tuned per
/// [brightness] so the initial stays legible in both themes.
Color roomAvatarColor(String name, Brightness brightness) {
  var hash = 0;
  for (final unit in name.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  final hue = (hash % 360).toDouble();
  final lightness = brightness == Brightness.dark ? 0.42 : 0.55;
  return HSLColor.fromAHSL(1, hue, 0.55, lightness).toColor();
}
