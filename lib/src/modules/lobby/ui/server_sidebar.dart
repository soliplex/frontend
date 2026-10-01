import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../../../version.dart';
import '../../../core/app_identity.dart';
import '../../../core/ui/menu_row.dart';
import '../../auth/auth_tokens.dart';
import '../../auth/server_entry.dart';
import '../../auth/server_manager.dart';
import '../../auth/ui/server_sign_out_control.dart';
import '../../auth/user_claims.dart';
import '../../auth/ui/server_status_dot.dart';
import 'package:soliplex_design/soliplex_design.dart';

final Logger _logger = LogManager.instance.getLogger('soliplex.server_sidebar');

class ServerSidebar extends StatelessWidget {
  const ServerSidebar({
    super.key,
    required this.servers,
    required this.serverManager,
    required this.identity,
    required this.selectedServerId,
    required this.onSelectServer,
    required this.onSignIn,
    required this.onMarkServerRead,
    required this.onAddServer,
    required this.onDiagnostics,
    required this.onVersions,
  });

  final Map<String, ServerEntry> servers;

  /// Drives the per-tile destructive actions (log out / remove).
  final ServerManager serverManager;

  /// Brand identity shown in the header (logo + app name).
  final AppIdentity identity;

  /// The currently-viewed server; its tile is highlighted.
  final String? selectedServerId;

  /// Selects a server to view its rooms in the main pane.
  final void Function(String serverId) onSelectServer;

  /// Routes a disconnected server to its sign-in flow.
  final void Function(String serverId) onSignIn;

  /// Marks every room (and thread) on a server read, from its tile menu.
  final void Function(String serverId) onMarkServerRead;
  final VoidCallback onAddServer;
  final VoidCallback onDiagnostics;
  final VoidCallback onVersions;

  @override
  Widget build(BuildContext context) {
    // The account block reflects whoever is signed in on the selected
    // server (or Guest when there's no selection / no auth).
    final selectedEntry =
        selectedServerId == null ? null : servers[selectedServerId];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BrandHeader(identity: identity),
          const Divider(height: 1),
          Expanded(
            child: _ServerList(
              servers: servers,
              serverManager: serverManager,
              selectedServerId: selectedServerId,
              onSelectServer: onSelectServer,
              onSignIn: onSignIn,
              onMarkServerRead: onMarkServerRead,
              onAddServer: onAddServer,
            ),
          ),
          const Divider(height: 1),
          _AccountBar(
            entry: selectedEntry,
            onDiagnostics: onDiagnostics,
            onVersions: onVersions,
          ),
        ],
      ),
    );
  }
}

/// Branded sidebar header: the flavor's logo, app name, and the running
/// library version. Whitelabel forks change the logo and name through the
/// identity API; the version is the shipped `soliplexVersion` constant.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.identity});

  /// Logo box size. Kept close to the title + version block so the mark
  /// reads as part of the header rather than dominating it; the flavor's
  /// logo is scaled to fit regardless of its intrinsic size.
  static const double _logoSize = 40;

  final AppIdentity identity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(SoliplexSpacing.s4),
      child: Row(
        children: [
          SizedBox.square(
            dimension: _logoSize,
            child: FittedBox(
              fit: BoxFit.contain,
              child: BrandLogo(identity: identity),
            ),
          ),
          const SizedBox(width: SoliplexSpacing.s6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  identity.appName,
                  style: context.brandNameOn(theme.textTheme.titleMedium),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'v$soliplexVersion',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerList extends StatelessWidget {
  const _ServerList({
    required this.servers,
    required this.serverManager,
    required this.selectedServerId,
    required this.onSelectServer,
    required this.onSignIn,
    required this.onMarkServerRead,
    required this.onAddServer,
  });

  final Map<String, ServerEntry> servers;
  final ServerManager serverManager;
  final String? selectedServerId;
  final void Function(String serverId) onSelectServer;
  final void Function(String serverId) onSignIn;
  final void Function(String serverId) onMarkServerRead;
  final VoidCallback onAddServer;

  @override
  Widget build(BuildContext context) {
    // Selected server first, then the shared display order, so the tile beside
    // the visible rooms never scrolls away. Selecting does reorder the list;
    // accepted because selection is occasional. Safe to mutate in place —
    // serversInDisplayOrder returns a fresh list.
    final ordered = serversInDisplayOrder(servers.values);
    final selectedIndex =
        ordered.indexWhere((e) => e.serverId == selectedServerId);
    if (selectedIndex > 0) ordered.insert(0, ordered.removeAt(selectedIndex));

    return ListView(
      children: [
        Padding(
          // Per-server actions live in each tile's ⋮ menu, so this is just a
          // section label.
          padding: const EdgeInsets.fromLTRB(SoliplexSpacing.s4,
              SoliplexSpacing.s4, SoliplexSpacing.s4, SoliplexSpacing.s2),
          child: Text(
            'Servers (${servers.length})',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        for (final entry in ordered)
          _ServerTile(
            // Keyed by server, because this list reorders (the pin, and rank
            // on sign-in). Without it ListView matches elements by index, so a
            // reorder drops a tile's live log-out state — its spinner or its
            // error.
            key: ValueKey(entry.serverId),
            entry: entry,
            serverManager: serverManager,
            selected: entry.serverId == selectedServerId,
            onTap: () => onSelectServer(entry.serverId),
            onSignIn: () => onSignIn(entry.serverId),
            onMarkAllRead: () => onMarkServerRead(entry.serverId),
          ),
        Padding(
          padding: const EdgeInsets.only(top: SoliplexSpacing.s2),
          child: SoliplexButton.outlined(
            onPressed: onAddServer,
            icon: const Icon(Icons.add, size: 18),
            child: const Text('Add Server'),
          ),
        ),
      ],
    );
  }
}

class _ServerTile extends StatefulWidget {
  const _ServerTile({
    super.key,
    required this.entry,
    required this.serverManager,
    required this.selected,
    required this.onTap,
    required this.onSignIn,
    required this.onMarkAllRead,
  });

  final ServerEntry entry;
  final ServerManager serverManager;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onSignIn;
  final VoidCallback onMarkAllRead;

  @override
  State<_ServerTile> createState() => _ServerTileState();
}

class _ServerTileState extends State<_ServerTile> {
  bool _hovered = false;

  /// Opens the trailing ⋮ menu from the tile's long-press and secondary tap.
  ///
  /// `currentState` is null exactly while a log-out is outstanding or its
  /// failure is showing, because the menu is not built then — the slot holds a
  /// spinner or an error button — so the gestures go inert without a flag to
  /// keep in step. A hidden menu is still built (`Visibility.maintainState`),
  /// which is what lets an unselected tile, the case with no visible ⋮, answer
  /// the gesture at all.
  final _menuKey = GlobalKey<PopupMenuButtonState<_ServerTileAction>>();

  @override
  Widget build(BuildContext context) {
    // No auth/identity subtitle: the account block shows who's signed in on the
    // selected server, and the tile's ⋮ menu reflects connection state (Sign in
    // vs Log out).
    //
    // The ⋮ reveals on hover (desktop); the selected tile keeps it shown so the
    // actions stay reachable without a mouse (touch, or the active server). A
    // hidden ⋮ still holds its space, so revealing one does not shift the
    // title — see [_ServerTileMenu.build], which also decides that a
    // spinner or an error ignores this flag entirely.
    final showMenu = _hovered || widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      // Long-press and right-click open the ⋮ menu directly — hover never
      // fires on touch, so an unselected tile would otherwise have no
      // reachable actions without first selecting the server.
      child: GestureDetector(
        onLongPress: () => _menuKey.currentState?.showButtonMenu(),
        onSecondaryTap: () => _menuKey.currentState?.showButtonMenu(),
        child: ListTile(
          // ListTile pads both sides by 16 unless told otherwise. Drop the right
          // pad so the ⋮ reaches the tile's edge; the button keeps its own
          // padding, so the glyph still clears the rounded corner and the tap
          // target stays full size.
          contentPadding: const EdgeInsets.only(left: SoliplexSpacing.s4),
          // Tighten the slot so the dot reads as a marker beside the name
          // rather than a far-left icon.
          leading: ServerStatusDot.leadingSlot(widget.entry),
          minLeadingWidth: 0,
          horizontalTitleGap: SoliplexSpacing.s3,
          selected: widget.selected,
          // Prefer the server's human-readable name; fall back to the address,
          // without its scheme so it reads the same here as in the room header.
          // The tile shows only the label — the full address is reachable (and
          // copyable) from the ⋮ menu's "Copy server address" action.
          title: Text(
            widget.entry.listLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: _ServerTileMenu(
            menuKey: _menuKey,
            revealed: showMenu,
            entry: widget.entry,
            serverManager: widget.serverManager,
            onSignIn: widget.onSignIn,
            onMarkAllRead: widget.onMarkAllRead,
          ),
          dense: true,
          onTap: widget.onTap,
        ),
      ),
    );
  }
}

/// Per-server actions behind a tile's trailing ⋮ menu. The available set
/// depends on the server's connection state (see [_ServerTileMenu]).
enum _ServerTileAction { signIn, logOut, markAllRead, copyAddress, remove }

/// A server tile's ⋮ menu: sign in / log out / remove, scoped to one
/// [ServerEntry]. Log out and remove go through [ServerSignOutControl], which
/// replaces the ⋮ with a spinner while the IdP round-trip runs and with an
/// error button when it fails.
class _ServerTileMenu extends StatelessWidget {
  const _ServerTileMenu({
    required this.menuKey,
    required this.revealed,
    required this.entry,
    required this.serverManager,
    required this.onSignIn,
    required this.onMarkAllRead,
  });

  /// Handed to the inner [PopupMenuButton] so the tile's gestures can open it.
  /// Typed to that state, not to [Key], because any other key compiles and
  /// then silently leaves both gestures dead.
  final GlobalKey<PopupMenuButtonState<_ServerTileAction>> menuKey;

  /// Whether the idle ⋮ is shown. A spinner or an error ignores this and shows
  /// regardless — see [build].
  final bool revealed;

  final ServerEntry entry;
  final ServerManager serverManager;
  final VoidCallback onSignIn;
  final VoidCallback onMarkAllRead;

  /// Copies the server's full address to the clipboard and confirms with a
  /// SnackBar. Captures the messenger before the async gap so the post-await
  /// use doesn't depend on a possibly-unmounted context.
  Future<void> _copyAddress(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final address = formatServerUrl(entry.serverUrl);
    try {
      await Clipboard.setData(ClipboardData(text: address));
    } on Exception catch (e, st) {
      _logger.warning(
        'Clipboard.setData failed',
        error: e,
        stackTrace: st,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not copy server address')),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text('Copied $address')),
    );
  }

  @override
  Widget build(BuildContext context) {
    // A spinner and an error both show unconditionally: only the idle ⋮ is
    // hidden by [revealed]. An outcome the user cannot see is worse than a
    // busy-looking tile, and a long-press can start a removal on a tile that
    // never reveals its ⋮ — hiding the result would leave the failure with
    // nowhere to appear.
    return ServerSignOutControl(
      entry: entry,
      serverManager: serverManager,
      idleBuilder: (context, {required signOut, required remove}) => Visibility(
        visible: revealed,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: PopupMenuButton<_ServerTileAction>(
          key: menuKey,
          icon: const Icon(Icons.more_vert),
          tooltip: 'Server actions',
          onSelected: (action) {
            switch (action) {
              case _ServerTileAction.signIn:
                onSignIn();
              case _ServerTileAction.logOut:
                signOut();
              case _ServerTileAction.markAllRead:
                onMarkAllRead();
              case _ServerTileAction.copyAddress:
                _copyAddress(context);
              case _ServerTileAction.remove:
                remove();
            }
          },
          itemBuilder: (context) => [
            if (!entry.isConnected)
              const PopupMenuItem(
                value: _ServerTileAction.signIn,
                child: MenuRow(icon: Icons.login, label: 'Sign in'),
              ),
            if (entry.hasSession)
              const PopupMenuItem(
                value: _ServerTileAction.logOut,
                child: MenuRow(icon: Icons.logout, label: 'Log out'),
              ),
            const PopupMenuItem(
              value: _ServerTileAction.markAllRead,
              child: MenuRow(
                icon: Icons.mark_chat_read_outlined,
                label: 'Mark all as read',
              ),
            ),
            const PopupMenuItem(
              value: _ServerTileAction.copyAddress,
              child: MenuRow(
                icon: Icons.content_copy,
                label: 'Copy server address',
              ),
            ),
            PopupMenuItem(
              value: _ServerTileAction.remove,
              child: MenuRow(
                icon: Icons.delete_outline,
                label: 'Remove',
                destructive: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The actions collapsed behind the sidebar's "more" (⋮) menu. These are
/// developer/utility destinations, deliberately de-emphasised vs. the account
/// block they sit beside. ("Home" is intentionally absent — the Add Server
/// button already routes to the home screen.)
enum _SidebarAction { diagnostics, versions }

/// Sidebar footer: the signed-in account on the left, a ⋮ menu of utility
/// actions on the right.
class _AccountBar extends StatelessWidget {
  const _AccountBar({
    required this.entry,
    required this.onDiagnostics,
    required this.onVersions,
  });

  final ServerEntry? entry;
  final VoidCallback onDiagnostics;
  final VoidCallback onVersions;

  void _onSelected(_SidebarAction action) {
    switch (action) {
      case _SidebarAction.diagnostics:
        onDiagnostics();
      case _SidebarAction.versions:
        onVersions();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          SoliplexSpacing.s2, SoliplexSpacing.s2, 0, SoliplexSpacing.s2),
      child: Row(
        children: [
          Expanded(child: _AccountBlock(entry: entry)),
          const SizedBox(width: SoliplexSpacing.s2),
          PopupMenuButton<_SidebarAction>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More',
            onSelected: _onSelected,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _SidebarAction.diagnostics,
                child: MenuRow(icon: Icons.troubleshoot, label: 'Diagnostics'),
              ),
              PopupMenuItem(
                value: _SidebarAction.versions,
                child: MenuRow(icon: Icons.info_outline, label: 'Versions'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The account identity for the selected server: name, optional email, and a
/// colored initial avatar. Falls back to a "Guest" identity when the server
/// is unauthenticated or in no-auth mode.
class _AccountBlock extends StatelessWidget {
  const _AccountBlock({required this.entry});

  final ServerEntry? entry;

  @override
  Widget build(BuildContext context) {
    // Session and token claims are per-entry signals the parent does not
    // watch; Watch rebuilds the block when the session flips (e.g. sign-in /
    // expiry) or the claims change (e.g. a token refresh) without a map
    // mutation.
    return Watch((context) {
      final theme = Theme.of(context);
      final identity = _resolveIdentity();
      return Row(
        children: [
          _Avatar(initial: identity.name.characters.first.toUpperCase()),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  identity.name,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (identity.email != null)
                  Text(
                    identity.email!,
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
    });
  }

  UserAccount _resolveIdentity() {
    final isAuthenticated = entry != null &&
        entry!.requiresAuth &&
        entry!.auth.session.value is ActiveSession;
    if (!isAuthenticated) {
      return (name: 'Guest', email: null);
    }
    return accountFromClaims(entry!.auth.currentUserClaims.value);
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initial});

  /// Avatar side, sized to the two-line name/email block. Not tokenised —
  /// there is no avatar-size token.
  static const double _size = 36;

  final String initial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(context.radii.sm),
      ),
      child: Text(
        initial,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
