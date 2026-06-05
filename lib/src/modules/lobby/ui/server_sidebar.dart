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
    return Column(
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
        _ActionButtons(
          onAddServer: onAddServer,
          onNetworkInspector: onNetworkInspector,
          onVersions: onVersions,
        ),
      ],
    );
  }
}

/// Branded sidebar header: the flavor's logo, app name, and the running
/// library version. Whitelabel forks change the logo and name through the
/// branding API; the version is the shipped `soliplexVersion` constant.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.branding});

  /// Logo box height. Kept close to the title + version block so the mark
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
          const SizedBox(width: SoliplexSpacing.s4),
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
          // s3 above lifts the button off the last server tile.
          padding: const EdgeInsets.fromLTRB(SoliplexSpacing.s2,
              SoliplexSpacing.s3, SoliplexSpacing.s2, SoliplexSpacing.s2),
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

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.onAddServer,
    required this.onNetworkInspector,
    required this.onVersions,
  });

  final VoidCallback onAddServer;
  final VoidCallback onNetworkInspector;
  final VoidCallback onVersions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SoliplexButton.text(
          onPressed: onAddServer,
          child: const Text('Home'),
        ),
        SoliplexButton.text(
          onPressed: onNetworkInspector,
          child: const Text('Network Inspector'),
        ),
        SoliplexButton.text(
          onPressed: onVersions,
          child: const Text('Versions'),
        ),
      ],
    );
  }
}
