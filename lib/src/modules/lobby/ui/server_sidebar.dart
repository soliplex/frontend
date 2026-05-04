import 'package:flutter/material.dart';

import '../../../../soliplex_frontend.dart';
import '../../../shared/theme_toggle_button.dart';
import '../../auth/server_entry.dart';
import '../lobby_state.dart';

class ServerSidebar extends StatelessWidget {
  const ServerSidebar({
    super.key,
    required this.servers,
    required this.profiles,
    required this.onServerTap,
    required this.onAddServer,
    required this.onNetworkInspector,
    required this.onVersions,
  });

  final Map<String, ServerEntry> servers;
  final Map<String, UserProfile?> profiles;
  final VoidCallback onServerTap;
  final VoidCallback onAddServer;
  final VoidCallback onNetworkInspector;
  final VoidCallback onVersions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _ServerList(
            servers: servers,
            profiles: profiles,
            onServerTap: onServerTap,
            onAddServer: onAddServer,
          ),
        ),
        const Divider(),
        _ActionButtons(
          onAddServer: onAddServer,
          onNetworkInspector: onNetworkInspector,
          onVersions: onVersions,
        ),
      ],
    );
  }
}

class _ServerList extends StatelessWidget {
  const _ServerList({
    required this.servers,
    required this.profiles,
    required this.onServerTap,
    required this.onAddServer,
  });

  final Map<String, ServerEntry> servers;
  final Map<String, UserProfile?> profiles;
  final VoidCallback onServerTap;
  final VoidCallback onAddServer;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              SoliplexSpacing.s5, SoliplexSpacing.s4, 0, SoliplexSpacing.s3),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Servers (${servers.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const ThemeToggleButton(),
            ],
          ),
        ),
        const Divider(),
        for (final entry in servers.entries)
          _ServerTile(
            entry: entry.value,
            profile: profiles[entry.key],
            onTap: onServerTap,
          ),
        TextButton.icon(
          onPressed: onAddServer,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Server'),
          style: TextButton.styleFrom(alignment: Alignment.centerLeft),
        ),
      ],
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.entry,
    required this.profile,
    required this.onTap,
  });

  final ServerEntry entry;
  final UserProfile? profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(formatServerUrl(entry.serverUrl)),
      subtitle: Text(_identityLabel),
      dense: true,
      onTap: onTap,
    );
  }

  String get _identityLabel {
    if (!entry.requiresAuth) return 'No authentication required';
    if (!entry.isConnected) return 'Not signed in';
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
        TextButton.icon(
          onPressed: onAddServer,
          icon: const Icon(Icons.home, size: 16),
          label: const Text('Home'),
          style: TextButton.styleFrom(alignment: Alignment.centerLeft),
        ),
        const Divider(),
        TextButton.icon(
          onPressed: onNetworkInspector,
          icon: const Icon(Icons.lan, size: 16),
          label: const Text('Network Inspector'),
          style: TextButton.styleFrom(alignment: Alignment.centerLeft),
        ),
        TextButton(
          onPressed: onVersions,
          child: const Text('Versions'),
        ),
      ],
    );
  }
}
