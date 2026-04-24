import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design/theme/theme_extensions.dart';
import '../../../shared/theme_toggle_button.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_agent/soliplex_agent.dart'
    show fetchOidcDiscoveryDocument;

import '../auth_providers.dart';
import '../auth_tokens.dart';
import '../server_entry.dart';
import '../server_manager.dart';

class ServerListScreen extends ConsumerStatefulWidget {
  const ServerListScreen({super.key, required this.serverManager});

  final ServerManager serverManager;

  @override
  ConsumerState<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends ConsumerState<ServerListScreen> {
  late final void Function() _unsubscribe;

  @override
  void initState() {
    super.initState();
    _unsubscribe = widget.serverManager.servers.subscribe((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final servers = widget.serverManager.servers.value;
    final connected = servers.values.where((e) => e.isConnected).toList();
    final disconnected = servers.values.where((e) => !e.isConnected).toList();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Servers'),
        titleTextStyle: SoliplexTheme.appBarTitleStyle(context),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () => context.go('/'),
            child: const Text('Home'),
          ),
          if (connected.isNotEmpty)
            TextButton(
              onPressed: () => context.go('/lobby'),
              child: const Text('Lobby'),
            ),
          const ThemeToggleButton(),
        ],
      ),
      body: ListView(
        children: [
          if (connected.isNotEmpty) ...[
            _sectionHeader(theme, 'Connected (${connected.length})'),
            for (final entry in connected) _connectedTile(theme, entry),
          ],
          if (disconnected.isNotEmpty) ...[
            _sectionHeader(theme, 'Disconnected (${disconnected.length})'),
            for (final entry in disconnected) _disconnectedTile(theme, entry),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _connectedTile(ThemeData theme, ServerEntry entry) {
    return ListTile(
      title: Text(formatServerUrl(entry.serverUrl)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (entry.requiresAuth)
            TextButton(
              onPressed: () => _logout(entry),
              child: const Text('Log out'),
            ),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              color: theme.colorScheme.error,
            ),
            onPressed: () async {
              await _logout(entry);
              widget.serverManager.removeServer(entry.serverId);
            },
          ),
        ],
      ),
      onTap: () => context.go('/lobby'),
    );
  }

  Widget _disconnectedTile(ThemeData theme, ServerEntry entry) {
    return ListTile(
      title: Text(formatServerUrl(entry.serverUrl)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () {
              final url = Uri.encodeComponent(entry.serverUrl.toString());
              context.go('/?url=$url');
            },
            child: const Text('Sign in'),
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              color: theme.colorScheme.error,
            ),
            onPressed: () => widget.serverManager.removeServer(entry.serverId),
          ),
        ],
      ),
      onTap: () {
        final url = Uri.encodeComponent(entry.serverUrl.toString());
        context.go('/?url=$url');
      },
    );
  }

  Future<void> _logout(ServerEntry entry) async {
    final authFlow = ref.read(authFlowProvider);
    final session = entry.auth.session.value;
    entry.auth.logout();
    if (mounted) setState(() {});
    if (session is ActiveSession) {
      String? endSessionEndpoint;
      try {
        final httpClient = ref.read(probeClientProvider);
        final discovery = await fetchOidcDiscoveryDocument(
          Uri.parse(session.provider.discoveryUrl),
          httpClient,
        );
        endSessionEndpoint = discovery.endSessionEndpoint?.toString();
      } catch (e, st) {
        dev.log('OIDC discovery failed during logout',
            error: e, stackTrace: st);
      }
      if (!mounted) return;
      await authFlow.endSession(
        discoveryUrl: session.provider.discoveryUrl,
        endSessionEndpoint: endSessionEndpoint,
        idToken: session.tokens.idToken ?? '',
        clientId: session.provider.clientId,
      );
    }
  }
}
