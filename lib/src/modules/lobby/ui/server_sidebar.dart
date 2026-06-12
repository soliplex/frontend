import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../../../version.dart';
import '../../../core/branding.dart';
import '../../auth/auth_providers.dart';
import '../../auth/auth_tokens.dart';
import '../../auth/server_entry.dart';
import '../../auth/server_logout.dart';
import '../../auth/server_manager.dart';
import '../lobby_state.dart';
import 'package:soliplex_design/soliplex_design.dart';

class ServerSidebar extends StatelessWidget {
  const ServerSidebar({
    super.key,
    required this.servers,
    required this.serverManager,
    required this.profiles,
    required this.branding,
    required this.selectedServerId,
    required this.onSelectServer,
    required this.onSignIn,
    required this.onAddServer,
    required this.onNetworkInspector,
    required this.onVersions,
  });

  final Map<String, ServerEntry> servers;

  /// Drives the per-tile destructive actions (log out / remove).
  final ServerManager serverManager;
  final Map<String, UserProfile?> profiles;

  /// Brand identity shown in the header (logo + app name).
  final SoliplexBranding branding;

  /// The currently-viewed server; its tile is highlighted.
  final String? selectedServerId;

  /// Selects a server to view its rooms in the main pane.
  final void Function(String serverId) onSelectServer;

  /// Routes a disconnected server to its sign-in flow.
  final void Function(String serverId) onSignIn;
  final VoidCallback onAddServer;
  final VoidCallback onNetworkInspector;
  final VoidCallback onVersions;

  @override
  Widget build(BuildContext context) {
    // The account block reflects whoever is signed in on the selected
    // server (or Guest when there's no selection / no auth).
    final selectedEntry =
        selectedServerId == null ? null : servers[selectedServerId];
    final selectedProfile =
        selectedServerId == null ? null : profiles[selectedServerId];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BrandHeader(branding: branding),
          const Divider(height: 1),
          Expanded(
            child: _ServerList(
              servers: servers,
              serverManager: serverManager,
              selectedServerId: selectedServerId,
              onSelectServer: onSelectServer,
              onSignIn: onSignIn,
              onAddServer: onAddServer,
            ),
          ),
          const Divider(height: 1),
          _AccountBar(
            entry: selectedEntry,
            profile: selectedProfile,
            onNetworkInspector: onNetworkInspector,
            onVersions: onVersions,
          ),
        ],
      ),
    );
  }
}

/// Branded sidebar header: the flavor's logo, app name, and the running
/// library version. Whitelabel forks change the logo and name through the
/// branding API; the version is the shipped `soliplexVersion` constant.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.branding});

  /// Logo box size. Kept close to the title + version block so the mark
  /// reads as part of the header rather than dominating it; the flavor's
  /// logo is scaled to fit regardless of its intrinsic size.
  static const double _logoSize = 40;

  final SoliplexBranding branding;

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
              child: BrandLogo(branding: branding),
            ),
          ),
          const SizedBox(width: SoliplexSpacing.s6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  branding.appName,
                  style: theme.textTheme.titleMedium,
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
    required this.onAddServer,
  });

  final Map<String, ServerEntry> servers;
  final ServerManager serverManager;
  final String? selectedServerId;
  final void Function(String serverId) onSelectServer;
  final void Function(String serverId) onSignIn;
  final VoidCallback onAddServer;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Padding(
          // Server management now lives in each tile's ⋮ menu, so the section
          // header is just a label.
          padding: const EdgeInsets.fromLTRB(SoliplexSpacing.s4,
              SoliplexSpacing.s4, SoliplexSpacing.s4, SoliplexSpacing.s2),
          child: Text(
            'Servers (${servers.length})',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        for (final entry in servers.entries)
          _ServerTile(
            entry: entry.value,
            serverManager: serverManager,
            selected: entry.key == selectedServerId,
            onTap: () => onSelectServer(entry.key),
            onSignIn: () => onSignIn(entry.key),
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
    required this.entry,
    required this.serverManager,
    required this.selected,
    required this.onTap,
    required this.onSignIn,
  });

  final ServerEntry entry;
  final ServerManager serverManager;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onSignIn;

  @override
  State<_ServerTile> createState() => _ServerTileState();
}

class _ServerTileState extends State<_ServerTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // No auth/identity subtitle: the account block shows who's signed in on the
    // selected server, and the tile's ⋮ menu reflects connection state (Sign in
    // vs Log out). The tile itself is just the server name.
    //
    // The ⋮ reveals on hover (desktop); the selected tile keeps it shown so the
    // actions stay reachable without a mouse (touch, or the active server). The
    // slot is always reserved (maintainSize) so the title doesn't shift.
    final showMenu = _hovered || widget.selected;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: ListTile(
        selected: widget.selected,
        title: Text(formatServerUrl(widget.entry.serverUrl)),
        trailing: Visibility(
          visible: showMenu,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: _ServerTileMenu(
            entry: widget.entry,
            serverManager: widget.serverManager,
            onSignIn: widget.onSignIn,
          ),
        ),
        dense: true,
        onTap: widget.onTap,
      ),
    );
  }
}

/// The signed-in user's display name from [profile], falling back through the
/// preferred username and email to a generic label when no name is set.
String _signedInName(UserProfile? profile) {
  if (profile == null) return 'Signed in';
  final full = '${profile.givenName} ${profile.familyName}'.trim();
  if (full.isNotEmpty) return full;
  if (profile.preferredUsername.isNotEmpty) return profile.preferredUsername;
  if (profile.email.isNotEmpty) return profile.email;
  return 'Signed in';
}

/// Per-server actions behind a tile's trailing ⋮ menu. The available set
/// depends on the server's connection state (see [_ServerTileMenu]).
enum _ServerTileAction { signIn, logOut, remove }

/// A server tile's ⋮ menu: sign in / log out / remove, scoped to one
/// [ServerEntry]. Owns its own log-out in-flight state (a spinner replaces the
/// ⋮ while the IdP round-trip runs) and reads the auth providers directly so
/// the destructive actions don't have to be threaded as async callbacks up
/// through the lobby. Log-out failures surface as a SnackBar; the local
/// session is preserved (see [logoutServer]).
class _ServerTileMenu extends ConsumerStatefulWidget {
  const _ServerTileMenu({
    required this.entry,
    required this.serverManager,
    required this.onSignIn,
  });

  final ServerEntry entry;
  final ServerManager serverManager;
  final VoidCallback onSignIn;

  @override
  ConsumerState<_ServerTileMenu> createState() => _ServerTileMenuState();
}

class _ServerTileMenuState extends ConsumerState<_ServerTileMenu> {
  bool _busy = false;

  Future<void> _handle(_ServerTileAction action) async {
    switch (action) {
      case _ServerTileAction.signIn:
        widget.onSignIn();
      case _ServerTileAction.logOut:
        await _runLogout(removeAfter: false);
      case _ServerTileAction.remove:
        // A connected, authenticated server logs out first so the IdP session
        // doesn't outlive the removed entry; everything else removes outright.
        if (widget.entry.isConnected && widget.entry.requiresAuth) {
          await _runLogout(removeAfter: true);
        } else {
          widget.serverManager.removeServer(widget.entry.serverId);
        }
    }
  }

  Future<void> _runLogout({required bool removeAfter}) async {
    // Capture the messenger before the await — removing the server rebuilds the
    // list and may unmount this tile before the future completes.
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await logoutServer(
        entry: widget.entry,
        authFlow: ref.read(authFlowProvider),
        probeClient: ref.read(probeClientProvider),
      );
      if (removeAfter) {
        widget.serverManager.removeServer(widget.entry.serverId);
      }
    } catch (e, st) {
      dev.log('Server logout failed', error: e, stackTrace: st);
      messenger.showSnackBar(
        SnackBar(content: Text('Log out failed: ${friendlyLogoutError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const SizedBox.square(
        dimension: 24,
        child: Padding(
          padding: EdgeInsets.all(SoliplexSpacing.s1),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final entry = widget.entry;
    final connected = entry.isConnected;
    return PopupMenuButton<_ServerTileAction>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'Server actions',
      onSelected: _handle,
      itemBuilder: (context) => [
        if (!connected)
          const PopupMenuItem(
            value: _ServerTileAction.signIn,
            child: _MenuRow(icon: Icons.login, label: 'Sign in'),
          ),
        if (connected && entry.requiresAuth)
          const PopupMenuItem(
            value: _ServerTileAction.logOut,
            child: _MenuRow(icon: Icons.logout, label: 'Log out'),
          ),
        PopupMenuItem(
          value: _ServerTileAction.remove,
          child: _MenuRow(
            icon: Icons.delete_outline,
            label: 'Remove',
            destructive: true,
          ),
        ),
      ],
    );
  }
}

/// The actions collapsed behind the sidebar's "more" (⋮) menu. These are
/// developer/utility destinations, deliberately de-emphasised vs. the account
/// block they sit beside. ("Home" is intentionally absent — the Add Server
/// button already routes to the home screen.)
enum _SidebarAction { networkInspector, versions }

/// Sidebar footer: the signed-in account on the left, a ⋮ menu of utility
/// actions on the right.
class _AccountBar extends StatelessWidget {
  const _AccountBar({
    required this.entry,
    required this.profile,
    required this.onNetworkInspector,
    required this.onVersions,
  });

  final ServerEntry? entry;
  final UserProfile? profile;
  final VoidCallback onNetworkInspector;
  final VoidCallback onVersions;

  void _onSelected(_SidebarAction action) {
    switch (action) {
      case _SidebarAction.networkInspector:
        onNetworkInspector();
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
          Expanded(child: _AccountBlock(entry: entry, profile: profile)),
          const SizedBox(width: SoliplexSpacing.s2),
          PopupMenuButton<_SidebarAction>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More',
            onSelected: _onSelected,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _SidebarAction.networkInspector,
                child: _MenuRow(
                    icon: Icons.lan_outlined, label: 'Network Inspector'),
              ),
              PopupMenuItem(
                value: _SidebarAction.versions,
                child: _MenuRow(icon: Icons.info_outline, label: 'Versions'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    this.destructive = false,
  });

  final IconData icon;
  final String label;

  /// Tints the row with `colorScheme.error` for a destructive action (Remove).
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Theme.of(context).colorScheme.error : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: SoliplexSpacing.s3),
        // Flexible so a long label (e.g. "Network Inspector") can't overflow
        // the menu's width; the menu widens to fit when there's room.
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: color == null ? null : TextStyle(color: color),
          ),
        ),
      ],
    );
  }
}

/// The account identity for the selected server: name, optional email, and a
/// colored initial avatar. Falls back to a "Guest" identity when the server
/// is unauthenticated or in no-auth mode.
class _AccountBlock extends StatelessWidget {
  const _AccountBlock({required this.entry, required this.profile});

  final ServerEntry? entry;
  final UserProfile? profile;

  @override
  Widget build(BuildContext context) {
    // Session is a per-entry signal the parent does not watch; Watch rebuilds
    // the block when it flips (e.g. sign-in / expiry) without a map mutation.
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

  ({String name, String? email}) _resolveIdentity() {
    final isAuthenticated = entry != null &&
        entry!.requiresAuth &&
        entry!.auth.session.value is ActiveSession;
    if (!isAuthenticated) {
      return (name: 'Guest', email: null);
    }
    final email = (profile?.email.isNotEmpty ?? false) ? profile!.email : null;
    return (name: _signedInName(profile), email: email);
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
        borderRadius: BorderRadius.circular(soliplexRadii.sm),
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
