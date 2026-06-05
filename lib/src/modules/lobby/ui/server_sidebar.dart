import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../../../version.dart';
import '../../../core/branding.dart';
import '../../auth/auth_tokens.dart';
import '../../auth/server_entry.dart';
import '../lobby_state.dart';
import 'package:soliplex_design/soliplex_design.dart';

class ServerSidebar extends StatelessWidget {
  const ServerSidebar({
    super.key,
    required this.servers,
    required this.profiles,
    required this.branding,
    required this.selectedServerId,
    required this.onSelectServer,
    required this.onServerTap,
    required this.onAddServer,
    required this.onNetworkInspector,
    required this.onVersions,
  });

  final Map<String, ServerEntry> servers;
  final Map<String, UserProfile?> profiles;

  /// Brand identity shown in the header (logo + app name).
  final SoliplexBranding branding;

  /// The currently-viewed server; its tile is highlighted.
  final String? selectedServerId;

  /// Selects a server to view its rooms in the main pane.
  final void Function(String serverId) onSelectServer;

  /// Opens the server-management screen.
  final VoidCallback onServerTap;
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
      padding: EdgeInsets.symmetric(horizontal: SoliplexSpacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BrandHeader(branding: branding),
          const Divider(height: 1),
          Expanded(
            child: _ServerList(
              servers: servers,
              profiles: profiles,
              selectedServerId: selectedServerId,
              onSelectServer: onSelectServer,
              onServerTap: onServerTap,
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
    required this.profiles,
    required this.selectedServerId,
    required this.onSelectServer,
    required this.onServerTap,
    required this.onAddServer,
  });

  final Map<String, ServerEntry> servers;
  final Map<String, UserProfile?> profiles;
  final String? selectedServerId;
  final void Function(String serverId) onSelectServer;
  final VoidCallback onServerTap;
  final VoidCallback onAddServer;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(SoliplexSpacing.s4,
              SoliplexSpacing.s4, SoliplexSpacing.s2, SoliplexSpacing.s2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Servers (${servers.length})',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              // Server management lives behind this gear so a row tap is free
              // to select a server for viewing its rooms.
              IconButton(
                icon: const Icon(Icons.settings_outlined, size: 18),
                tooltip: 'Manage servers',
                onPressed: onServerTap,
              ),
            ],
          ),
        ),
        for (final entry in servers.entries)
          _ServerTile(
            entry: entry.value,
            profile: profiles[entry.key],
            selected: entry.key == selectedServerId,
            onTap: () => onSelectServer(entry.key),
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

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.entry,
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final ServerEntry entry;
  final UserProfile? profile;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: selected,
      title: Text(formatServerUrl(entry.serverUrl)),
      // The label depends on entry.auth.session, which the parent does
      // not watch — Watch rebuilds the subtitle on session flips.
      subtitle: Watch(
        (context) => Text(_identityLabel(entry.auth.session.value)),
      ),
      dense: true,
      onTap: onTap,
    );
  }

  String _identityLabel(SessionState session) {
    if (!entry.requiresAuth) return 'No authentication required';
    return switch (session) {
      ExpiredSession() => 'Session expired',
      NoSession() => 'Not signed in',
      ActiveSession() => _activeIdentityLabel(),
    };
  }

  String _activeIdentityLabel() {
    if (profile == null) return 'Signed in';
    final name = '${profile!.givenName} ${profile!.familyName}'.trim();
    if (name.isNotEmpty) return name;
    if (profile!.email.isNotEmpty) return profile!.email;
    return 'Signed in';
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
        // Flexible so a long label (e.g. "Network Inspector") can't overflow
        // the menu's width; the menu widens to fit when there's room.
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
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
          _Avatar(initial: identity.initial),
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

  ({String name, String? email, String initial}) _resolveIdentity() {
    final isAuthenticated = entry != null &&
        entry!.requiresAuth &&
        entry!.auth.session.value is ActiveSession;
    if (!isAuthenticated) {
      return (name: 'Guest', email: null, initial: 'G');
    }
    final name = _displayName(profile);
    final email = (profile?.email.isNotEmpty ?? false) ? profile!.email : null;
    final initial = name.substring(0, 1).toUpperCase();
    return (name: name, email: email, initial: initial);
  }

  String _displayName(UserProfile? profile) {
    if (profile == null) return 'Signed in';
    final full = '${profile.givenName} ${profile.familyName}'.trim();
    if (full.isNotEmpty) return full;
    if (profile.preferredUsername.isNotEmpty) return profile.preferredUsername;
    if (profile.email.isNotEmpty) return profile.email;
    return 'Signed in';
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initial});

  /// Avatar side. Sized to the two-line name/email block, not tokenised
  /// (there is no avatar-size token), consistent with other icon sizes.
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
