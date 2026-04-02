import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../auth/server_entry.dart';
import '../../auth/server_manager.dart';
import '../lobby_state.dart';
import 'room_card.dart';
import 'server_sidebar.dart';

const double _sidebarWidth = 240;
const double _wideBreakpoint = 600;

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key, required this.serverManager});

  final ServerManager serverManager;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  late final LobbyState _state;

  @override
  void initState() {
    super.initState();
    _state = LobbyState(serverManager: widget.serverManager);
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  void _onAddServer() => context.go('/');

  void _onSettings() {}

  void _onNetworkInspector() => context.push('/diagnostics/network');

  void _onRoomTap(String serverId, String roomId) {
    final entry = widget.serverManager.servers.value[serverId];
    assert(entry != null, 'Room tap for unknown serverId: $serverId');
    if (entry == null) return;
    context.go('/room/${entry.alias}/$roomId');
  }

  void _onInfoTap(String serverId, String roomId) {
    final entry = widget.serverManager.servers.value[serverId];
    assert(entry != null, 'Info tap for unknown serverId: $serverId');
    if (entry == null) return;
    context.push('/room/${entry.alias}/$roomId/info');
  }

  @override
  Widget build(BuildContext context) {
    final servers = widget.serverManager.servers.watch(context);
    final profiles = _state.userProfiles.watch(context);
    final roomsByServer = _state.roomsByServer.watch(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _wideBreakpoint;
        return isWide
            ? _WideLayout(
                servers: servers,
                profiles: profiles,
                roomsByServer: roomsByServer,
                onAddServer: _onAddServer,
                onSettings: _onSettings,
                onNetworkInspector: _onNetworkInspector,
                onRoomTap: _onRoomTap,
                onInfoTap: _onInfoTap,
              )
            : _NarrowLayout(
                servers: servers,
                profiles: profiles,
                roomsByServer: roomsByServer,
                onAddServer: _onAddServer,
                onSettings: _onSettings,
                onNetworkInspector: _onNetworkInspector,
                onRoomTap: _onRoomTap,
                onInfoTap: _onInfoTap,
              );
      },
    );
  }
}

class _WideLayout extends StatelessWidget {
  const _WideLayout({
    required this.servers,
    required this.profiles,
    required this.roomsByServer,
    required this.onAddServer,
    required this.onSettings,
    required this.onNetworkInspector,
    required this.onRoomTap,
    required this.onInfoTap,
  });

  final Map<String, ServerEntry> servers;
  final Map<String, UserProfile?> profiles;
  final Map<String, ServerRooms> roomsByServer;
  final VoidCallback onAddServer;
  final VoidCallback onSettings;
  final VoidCallback onNetworkInspector;
  final void Function(String serverId, String roomId) onRoomTap;
  final void Function(String serverId, String roomId) onInfoTap;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: _sidebarWidth,
            child: ServerSidebar(
              servers: servers,
              profiles: profiles,
              onAddServer: onAddServer,
              onSettings: onSettings,
              onNetworkInspector: onNetworkInspector,
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _RoomContent(
              roomsByServer: roomsByServer,
              servers: servers,
              onRoomTap: onRoomTap,
              onInfoTap: onInfoTap,
              onAddServer: onAddServer,
            ),
          ),
        ],
      ),
    );
  }
}

class _NarrowLayout extends StatelessWidget {
  const _NarrowLayout({
    required this.servers,
    required this.profiles,
    required this.roomsByServer,
    required this.onAddServer,
    required this.onSettings,
    required this.onNetworkInspector,
    required this.onRoomTap,
    required this.onInfoTap,
  });

  final Map<String, ServerEntry> servers;
  final Map<String, UserProfile?> profiles;
  final Map<String, ServerRooms> roomsByServer;
  final VoidCallback onAddServer;
  final VoidCallback onSettings;
  final VoidCallback onNetworkInspector;
  final void Function(String serverId, String roomId) onRoomTap;
  final void Function(String serverId, String roomId) onInfoTap;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      drawer: Drawer(
        child: ServerSidebar(
          servers: servers,
          profiles: profiles,
          onAddServer: onAddServer,
          onSettings: onSettings,
          onNetworkInspector: onNetworkInspector,
        ),
      ),
      body: _RoomContent(
        roomsByServer: roomsByServer,
        servers: servers,
        onRoomTap: onRoomTap,
        onInfoTap: onInfoTap,
        onAddServer: onAddServer,
      ),
    );
  }
}

class _RoomContent extends StatelessWidget {
  const _RoomContent({
    required this.roomsByServer,
    required this.servers,
    required this.onRoomTap,
    required this.onInfoTap,
    required this.onAddServer,
  });

  final Map<String, ServerRooms> roomsByServer;
  final Map<String, ServerEntry> servers;
  final void Function(String serverId, String roomId) onRoomTap;
  final void Function(String serverId, String roomId) onInfoTap;
  final VoidCallback onAddServer;

  @override
  Widget build(BuildContext context) {
    if (servers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No servers connected'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onAddServer,
              child: const Text('Add Server'),
            ),
          ],
        ),
      );
    }

    return ListView(
      children: [
        for (final entry in roomsByServer.entries)
          _ServerSection(
            serverId: entry.key,
            serverUrl: servers[entry.key]?.serverUrl,
            serverRooms: entry.value,
            onRoomTap: onRoomTap,
            onInfoTap: onInfoTap,
          ),
      ],
    );
  }
}

class _ServerSection extends StatelessWidget {
  const _ServerSection({
    required this.serverId,
    required this.serverUrl,
    required this.serverRooms,
    required this.onRoomTap,
    required this.onInfoTap,
  });

  final String serverId;
  final Uri? serverUrl;
  final ServerRooms serverRooms;
  final void Function(String serverId, String roomId) onRoomTap;
  final void Function(String serverId, String roomId) onInfoTap;

  @override
  Widget build(BuildContext context) {
    final heading = serverUrl != null ? formatServerUrl(serverUrl!) : serverId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            heading,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        switch (serverRooms) {
          RoomsLoading() => const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: LinearProgressIndicator(),
            ),
          RoomsFailed(:final error) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Failed to load rooms: $error'),
            ),
          RoomsLoaded(:final rooms) => Column(
              children: [
                for (final room in rooms)
                  RoomCard(
                    room: room,
                    onTap: () => onRoomTap(serverId, room.id),
                    onInfoTap: () => onInfoTap(serverId, room.id),
                  ),
              ],
            ),
        },
      ],
    );
  }
}
