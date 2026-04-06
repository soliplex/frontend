import 'package:flutter/material.dart';

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
  });

  final Map<String, ServerEntry> servers;
  final Map<String, UserProfile?> profiles;
  final VoidCallback onServerTap;
  final VoidCallback onAddServer;
  final VoidCallback onNetworkInspector;

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
        const Divider(height: 1),
        _ActionButtons(
          onAddServer: onAddServer,
          onNetworkInspector: onNetworkInspector,
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
            profile: profiles[entry.key],
            onTap: onServerTap,
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: OutlinedButton.icon(
            onPressed: onAddServer,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Server'),
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
  });

  final VoidCallback onAddServer;
  final VoidCallback onNetworkInspector;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton(
          onPressed: onAddServer,
          child: const Text('Home'),
        ),
        TextButton(
          onPressed: onNetworkInspector,
          child: const Text('Network Inspector'),
        ),
      ],
    );
  }
}
