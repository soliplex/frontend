import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show Room;
import 'package:soliplex_client/soliplex_client.dart'
    show PermissionDeniedException;

import '../../../core/branding.dart';
import '../../../core/routes.dart';
import '../../auth/server_entry.dart';
import '../../auth/server_manager.dart';
import '../lobby_sort_mode.dart';
import '../lobby_state.dart';
import '../lobby_view_mode.dart';
import '../room_activity_format.dart';
import 'room_card.dart';
import 'room_grid_card.dart';
import 'room_grid_layout.dart';
import 'server_sidebar.dart';
import 'package:soliplex_design/soliplex_design.dart';

const double _sidebarWidth = 240;

/// Fixed width of the sort dropdown on wide layouts, so it doesn't stretch to
/// the full row and crowd the view-mode toggle beside it.
const double _sortControlWidth = 184;

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({
    super.key,
    required this.serverManager,
    required this.branding,
    this.apiResolver,
  });

  final ServerManager serverManager;

  /// Brand identity for the sidebar header (logo + app name).
  final SoliplexBranding branding;

  /// Test seam forwarded to [LobbyState]; production uses the default
  /// per-entry API resolver.
  @visibleForTesting
  final ApiResolver? apiResolver;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  late final LobbyState _state;

  @override
  void initState() {
    super.initState();
    _state = LobbyState(
      serverManager: widget.serverManager,
      apiResolver: widget.apiResolver,
    );
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  void _onAddServer() => context.go(AppRoutes.home);

  void _onNetworkInspector() => context.push(AppRoutes.networkInspector);

  void _onVersions() => context.push(AppRoutes.versions);

  void _onRoomTap(String serverId, String roomId) {
    final entry = widget.serverManager.servers.value[serverId];
    assert(entry != null, 'Room tap for unknown serverId: $serverId');
    if (entry == null) return;
    context.go(AppRoutes.room(entry.alias, roomId));
  }

  void _onInfoTap(String serverId, String roomId) {
    final entry = widget.serverManager.servers.value[serverId];
    assert(entry != null, 'Info tap for unknown serverId: $serverId');
    if (entry == null) return;
    context.push(AppRoutes.roomInfo(entry.alias, roomId));
  }

  void _onSignIn(String serverId) {
    final entry = widget.serverManager.servers.value[serverId];
    assert(entry != null, 'Sign-in tap for unknown serverId: $serverId');
    if (entry == null) return;
    context.go(
      AppRoutes.homeWithUrl(
        entry.serverUrl.toString(),
        returnTo: AppRoutes.lobby,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final servers = widget.serverManager.servers.watch(context);
    final profiles = _state.userProfiles.watch(context);
    final roomsByServer = _state.roomsByServer.watch(context);
    final viewMode = _state.viewMode.watch(context);
    final searchQuery = _state.searchQuery.watch(context);
    final selectedServerId = _state.selectedServerId.watch(context);
    final sortMode = _state.sortMode.watch(context);
    final roomActivity = _state.roomActivity.watch(context);
    final activityLoading = _state.activityLoading.watch(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Persistent sidebar / two-pane layout is a desktop affordance; the
        // tablet band (600–840) uses the drawer, per the design spec.
        final isWide = constraints.maxWidth >= SoliplexBreakpoints.desktop;
        return isWide
            ? _WideLayout(
                servers: servers,
                profiles: profiles,
                branding: widget.branding,
                roomsByServer: roomsByServer,
                viewMode: viewMode,
                onViewModeChanged: _state.setViewMode,
                searchQuery: searchQuery,
                onSearchChanged: _state.setSearchQuery,
                sortMode: sortMode,
                onSortModeChanged: _state.setSortMode,
                roomActivity: roomActivity,
                activityLoading: activityLoading,
                selectedServerId: selectedServerId,
                onSelectServer: _state.selectServer,
                serverManager: widget.serverManager,
                onAddServer: _onAddServer,
                onNetworkInspector: _onNetworkInspector,
                onVersions: _onVersions,
                onRoomTap: _onRoomTap,
                onInfoTap: _onInfoTap,
                onSignIn: _onSignIn,
              )
            : _NarrowLayout(
                servers: servers,
                profiles: profiles,
                branding: widget.branding,
                roomsByServer: roomsByServer,
                viewMode: viewMode,
                onViewModeChanged: _state.setViewMode,
                searchQuery: searchQuery,
                onSearchChanged: _state.setSearchQuery,
                sortMode: sortMode,
                onSortModeChanged: _state.setSortMode,
                roomActivity: roomActivity,
                activityLoading: activityLoading,
                selectedServerId: selectedServerId,
                onSelectServer: _state.selectServer,
                serverManager: widget.serverManager,
                onAddServer: _onAddServer,
                onNetworkInspector: _onNetworkInspector,
                onVersions: _onVersions,
                onRoomTap: _onRoomTap,
                onInfoTap: _onInfoTap,
                onSignIn: _onSignIn,
              );
      },
    );
  }
}

class _WideLayout extends StatelessWidget {
  const _WideLayout({
    required this.servers,
    required this.profiles,
    required this.branding,
    required this.roomsByServer,
    required this.viewMode,
    required this.onViewModeChanged,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.sortMode,
    required this.onSortModeChanged,
    required this.roomActivity,
    required this.activityLoading,
    required this.selectedServerId,
    required this.onSelectServer,
    required this.serverManager,
    required this.onAddServer,
    required this.onNetworkInspector,
    required this.onVersions,
    required this.onRoomTap,
    required this.onInfoTap,
    required this.onSignIn,
  });

  final Map<String, ServerEntry> servers;
  final Map<String, UserProfile?> profiles;
  final SoliplexBranding branding;
  final Map<String, ServerRooms> roomsByServer;
  final LobbyViewMode viewMode;
  final void Function(LobbyViewMode) onViewModeChanged;
  final String searchQuery;
  final void Function(String) onSearchChanged;
  final LobbySortMode sortMode;
  final void Function(LobbySortMode) onSortModeChanged;
  final Map<RoomActivityKey, DateTime?> roomActivity;
  final bool activityLoading;
  final String? selectedServerId;
  final void Function(String serverId) onSelectServer;
  final ServerManager serverManager;
  final VoidCallback onAddServer;
  final VoidCallback onNetworkInspector;
  final VoidCallback onVersions;
  final void Function(String serverId, String roomId) onRoomTap;
  final void Function(String serverId, String roomId) onInfoTap;
  final void Function(String serverId) onSignIn;

  @override
  Widget build(BuildContext context) {
    // No AppBar in this two-pane layout, so SafeArea keeps the sidebar and
    // room pane clear of the status bar, home indicator, and side notches.
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            SizedBox(
              width: _sidebarWidth,
              child: ServerSidebar(
                servers: servers,
                serverManager: serverManager,
                profiles: profiles,
                branding: branding,
                selectedServerId: selectedServerId,
                onSelectServer: onSelectServer,
                onSignIn: onSignIn,
                onAddServer: onAddServer,
                onNetworkInspector: onNetworkInspector,
                onVersions: onVersions,
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: _RoomContent(
                roomsByServer: roomsByServer,
                servers: servers,
                viewMode: viewMode,
                onViewModeChanged: onViewModeChanged,
                searchQuery: searchQuery,
                onSearchChanged: onSearchChanged,
                sortMode: sortMode,
                onSortModeChanged: onSortModeChanged,
                roomActivity: roomActivity,
                activityLoading: activityLoading,
                selectedServerId: selectedServerId,
                onRoomTap: onRoomTap,
                onInfoTap: onInfoTap,
                onAddServer: onAddServer,
                onSignIn: onSignIn,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NarrowLayout extends StatelessWidget {
  const _NarrowLayout({
    required this.servers,
    required this.profiles,
    required this.branding,
    required this.roomsByServer,
    required this.viewMode,
    required this.onViewModeChanged,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.sortMode,
    required this.onSortModeChanged,
    required this.roomActivity,
    required this.activityLoading,
    required this.selectedServerId,
    required this.onSelectServer,
    required this.serverManager,
    required this.onAddServer,
    required this.onNetworkInspector,
    required this.onVersions,
    required this.onRoomTap,
    required this.onInfoTap,
    required this.onSignIn,
  });

  final Map<String, ServerEntry> servers;
  final Map<String, UserProfile?> profiles;
  final SoliplexBranding branding;
  final Map<String, ServerRooms> roomsByServer;
  final LobbyViewMode viewMode;
  final void Function(LobbyViewMode) onViewModeChanged;
  final String searchQuery;
  final void Function(String) onSearchChanged;
  final LobbySortMode sortMode;
  final void Function(LobbySortMode) onSortModeChanged;
  final Map<RoomActivityKey, DateTime?> roomActivity;
  final bool activityLoading;
  final String? selectedServerId;
  final void Function(String serverId) onSelectServer;
  final ServerManager serverManager;
  final VoidCallback onAddServer;
  final VoidCallback onNetworkInspector;
  final VoidCallback onVersions;
  final void Function(String serverId, String roomId) onRoomTap;
  final void Function(String serverId, String roomId) onInfoTap;
  final void Function(String serverId) onSignIn;

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
        // A Drawer adds no inset of its own, so SafeArea keeps the brand
        // header and account bar clear of the status bar and home indicator.
        child: SafeArea(
          // Builder gives a context under this Scaffold so selecting a server
          // can close the drawer before revealing its rooms.
          child: Builder(
            builder: (drawerContext) => ServerSidebar(
              servers: servers,
              serverManager: serverManager,
              profiles: profiles,
              branding: branding,
              selectedServerId: selectedServerId,
              onSelectServer: (id) {
                onSelectServer(id);
                Scaffold.of(drawerContext).closeDrawer();
              },
              onSignIn: onSignIn,
              onAddServer: onAddServer,
              onNetworkInspector: onNetworkInspector,
              onVersions: onVersions,
            ),
          ),
        ),
      ),
      body: _RoomContent(
        roomsByServer: roomsByServer,
        servers: servers,
        viewMode: viewMode,
        onViewModeChanged: onViewModeChanged,
        searchQuery: searchQuery,
        onSearchChanged: onSearchChanged,
        sortMode: sortMode,
        onSortModeChanged: onSortModeChanged,
        roomActivity: roomActivity,
        activityLoading: activityLoading,
        selectedServerId: selectedServerId,
        onRoomTap: onRoomTap,
        onInfoTap: onInfoTap,
        onAddServer: onAddServer,
        onSignIn: onSignIn,
      ),
    );
  }
}

class _RoomContent extends StatelessWidget {
  const _RoomContent({
    required this.roomsByServer,
    required this.servers,
    required this.viewMode,
    required this.onViewModeChanged,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.sortMode,
    required this.onSortModeChanged,
    required this.roomActivity,
    required this.activityLoading,
    required this.selectedServerId,
    required this.onRoomTap,
    required this.onInfoTap,
    required this.onAddServer,
    required this.onSignIn,
  });

  final Map<String, ServerRooms> roomsByServer;
  final Map<String, ServerEntry> servers;
  final LobbyViewMode viewMode;
  final void Function(LobbyViewMode) onViewModeChanged;
  final String searchQuery;
  final void Function(String) onSearchChanged;
  final LobbySortMode sortMode;
  final void Function(LobbySortMode) onSortModeChanged;
  final Map<RoomActivityKey, DateTime?> roomActivity;
  final bool activityLoading;
  final String? selectedServerId;
  final void Function(String serverId, String roomId) onRoomTap;
  final void Function(String serverId, String roomId) onInfoTap;
  final VoidCallback onAddServer;
  final void Function(String serverId) onSignIn;

  @override
  Widget build(BuildContext context) {
    if (servers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No servers connected'),
            const SizedBox(height: SoliplexSpacing.s4),
            SoliplexButton.filled(
              onPressed: onAddServer,
              child: const Text('Add Server'),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Grid view is a tablet+/desktop affordance; below the tablet
        // breakpoint (phones) we force list and hide the view-mode toggle, so
        // the persisted choice is honoured again once the pane is wide enough.
        final allowGrid = constraints.maxWidth >= SoliplexBreakpoints.tablet;
        final effectiveViewMode = allowGrid ? viewMode : LobbyViewMode.list;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(SoliplexSpacing.s4,
                  SoliplexSpacing.s2, SoliplexSpacing.s4, 0),
              child: _LobbyControls(
                viewMode: viewMode,
                onViewModeChanged: onViewModeChanged,
                showViewModeToggle: allowGrid,
                searchQuery: searchQuery,
                onSearchChanged: onSearchChanged,
                sortMode: sortMode,
                onSortModeChanged: onSortModeChanged,
                sortLoading: activityLoading,
              ),
            ),
            Expanded(child: _buildSelectedServer(context, effectiveViewMode)),
          ],
        );
      },
    );
  }

  Widget _buildSelectedServer(BuildContext context, LobbyViewMode viewMode) {
    final id = selectedServerId;
    // No selection yet — the persisted choice loads asynchronously on launch.
    // Show the same loading indicator the rooms-loading state uses so cold
    // start reads as spinner -> rooms with no flash of a blank pane.
    if (id == null) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: SoliplexSpacing.s4),
            child: LinearProgressIndicator(),
          ),
        ],
      );
    }
    // Every server in the set has a room state by the time it can be selected:
    // _onServersChanged fetches (-> RoomsLoading) for a connected server, and
    // its synchronous auth-subscription fire routes a not-connected one through
    // _onAuthChanged (-> RoomsExpired / RoomsSignedOut). A missing entry should
    // not happen; assert in debug and fall back to a blank pane in release
    // rather than throwing in front of the user.
    final serverRooms = roomsByServer[id];
    if (serverRooms == null) {
      assert(false, 'Selected server "$id" has no room state');
      return const SizedBox.shrink();
    }

    return ListView(
      // The sidebar names the selected server, so the pane omits an address
      // heading; the top padding stands in for it.
      padding: const EdgeInsets.only(top: SoliplexSpacing.s2),
      children: [
        _ServerSection(
          serverId: id,
          serverRooms: serverRooms,
          viewMode: viewMode,
          searchQuery: searchQuery,
          sortMode: sortMode,
          roomActivity: roomActivity,
          onRoomTap: onRoomTap,
          onInfoTap: onInfoTap,
          onSignIn: onSignIn,
        ),
      ],
    );
  }
}

/// The lobby's control row: a room-name filter and the view-mode toggle.
///
/// Stateful so the search field's [TextEditingController] survives the
/// signal-driven rebuilds (every keystroke updates the query signal) and
/// the wide/narrow layout switch. On narrow widths the search field takes
/// the full width and the toggle drops below it.
class _LobbyControls extends StatefulWidget {
  const _LobbyControls({
    required this.viewMode,
    required this.onViewModeChanged,
    required this.showViewModeToggle,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.sortMode,
    required this.onSortModeChanged,
    required this.sortLoading,
  });

  final LobbyViewMode viewMode;
  final void Function(LobbyViewMode) onViewModeChanged;

  /// Whether to show the list/grid toggle. Hidden on phones, where the view
  /// is forced to list.
  final bool showViewModeToggle;
  final String searchQuery;
  final void Function(String) onSearchChanged;
  final LobbySortMode sortMode;
  final void Function(LobbySortMode) onSortModeChanged;
  final bool sortLoading;

  @override
  State<_LobbyControls> createState() => _LobbyControlsState();
}

class _LobbyControlsState extends State<_LobbyControls> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.searchQuery)
      ..addListener(_handleChanged);
  }

  void _handleChanged() {
    widget.onSearchChanged(_controller.text);
    // Refresh the clear-button affordance as the field empties/fills.
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_handleChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = SoliplexInput(
      controller: _controller,
      hintText: 'Filter rooms',
      leadingIcon: const Icon(Icons.search),
      textInputAction: TextInputAction.search,
      trailingIcon: _controller.text.isEmpty
          ? null
          : IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Clear filter',
              onPressed: _controller.clear,
            ),
    );
    final toggle = widget.showViewModeToggle
        ? _ViewModeToggle(
            viewMode: widget.viewMode,
            onChanged: widget.onViewModeChanged,
          )
        : null;
    // "Recent activity" is derived from each room's newest thread (the backend
    // has no last-access field), so it can take a moment to populate; the
    // dropdown stays live (so the user can switch back) and a small spinner
    // sits beside it while the sweep runs.
    final sort = SoliplexDropdown<LobbySortMode>(
      leadingIcon: const Icon(Icons.sort),
      initialValue: widget.sortMode,
      onSelected: (mode) =>
          widget.onSortModeChanged(mode ?? LobbySortMode.none),
      entries: const [
        SoliplexDropdownEntry(value: LobbySortMode.none, label: 'None'),
        SoliplexDropdownEntry(
          value: LobbySortMode.recentActivity,
          label: 'Recent activity',
        ),
      ],
    );
    final busy =
        widget.sortLoading && widget.sortMode == LobbySortMode.recentActivity
            ? const Padding(
                padding: EdgeInsets.only(left: SoliplexSpacing.s2),
                child: SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= SoliplexBreakpoints.tablet) {
          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: SoliplexSpacing.s3),
              SizedBox(width: _sortControlWidth, child: sort),
              busy,
              if (toggle != null) ...[
                const SizedBox(width: SoliplexSpacing.s3),
                toggle,
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            search,
            const SizedBox(height: SoliplexSpacing.s2),
            Row(
              children: [
                Expanded(child: sort),
                busy,
                if (toggle != null) ...[
                  const SizedBox(width: SoliplexSpacing.s3),
                  toggle,
                ],
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({required this.viewMode, required this.onChanged});

  final LobbyViewMode viewMode;
  final void Function(LobbyViewMode) onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<LobbyViewMode>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: LobbyViewMode.list,
          icon: Icon(Icons.view_list),
          tooltip: 'List view',
        ),
        ButtonSegment(
          value: LobbyViewMode.grid,
          icon: Icon(Icons.grid_view),
          tooltip: 'Grid view',
        ),
      ],
      selected: {viewMode},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class _ServerSection extends StatelessWidget {
  const _ServerSection({
    required this.serverId,
    required this.serverRooms,
    required this.viewMode,
    required this.searchQuery,
    required this.sortMode,
    required this.roomActivity,
    required this.onRoomTap,
    required this.onInfoTap,
    required this.onSignIn,
  });

  final String serverId;
  final ServerRooms serverRooms;
  final LobbyViewMode viewMode;
  final String searchQuery;
  final LobbySortMode sortMode;
  final Map<RoomActivityKey, DateTime?> roomActivity;
  final void Function(String serverId, String roomId) onRoomTap;
  final void Function(String serverId, String roomId) onInfoTap;
  final void Function(String serverId) onSignIn;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        switch (serverRooms) {
          RoomsLoading() => const Padding(
              padding: EdgeInsets.symmetric(horizontal: SoliplexSpacing.s4),
              child: LinearProgressIndicator(),
            ),
          RoomsFailed(:final error) => Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s4),
              child: Text(switch (error) {
                PermissionDeniedException() =>
                  "You don't have permission to view rooms on this server.",
                _ => 'Failed to load rooms: $error',
              }),
            ),
          RoomsLoaded(:final rooms) => _buildRooms(context, rooms),
          RoomsExpired() => _reauthPanel(
              context,
              title: 'Session expired',
              body: 'Sign in again to view rooms on this server.',
            ),
          RoomsSignedOut() => _reauthPanel(
              context,
              title: 'Signed out',
              body: 'Sign in to view rooms on this server.',
            ),
        },
      ],
    );
  }

  /// Inline panel for a not-connected server: a heading, a one-line
  /// explanation, and a button that routes to the server's sign-in flow.
  Widget _reauthPanel(
    BuildContext context, {
    required String title,
    required String body,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: SoliplexSpacing.s1),
          Text(body, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: SoliplexSpacing.s3),
          SoliplexButton.filled(
            onPressed: () => onSignIn(serverId),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
  }

  Widget _buildRooms(BuildContext context, List<Room> rooms) {
    final query = searchQuery.trim().toLowerCase();
    final matches = query.isEmpty
        ? rooms
        : rooms
            .where((room) => room.name.toLowerCase().contains(query))
            .toList();

    if (matches.isEmpty) {
      // A server with no rooms and no active filter renders nothing, as
      // before. The "no matches" copy is reserved for an active filter.
      if (query.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(
            SoliplexSpacing.s4, 0, SoliplexSpacing.s4, SoliplexSpacing.s2),
        child: Text(
          'No rooms match "${searchQuery.trim()}".',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    final ordered = _applySort(matches);

    // When sorting by recency, split the (already date-descending) list into
    // "Today / Yesterday / ..." sections, each under a header + divider — like
    // an LLM chat history. Otherwise render one flat block.
    if (sortMode != LobbySortMode.recentActivity) {
      return _buildBlock(context, ordered);
    }

    final groups = <ActivityBucket, List<Room>>{};
    for (final room in ordered) {
      (groups[bucketFor(_activityFor(room))] ??= []).add(room);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final bucket in ActivityBucket.values)
          if (groups[bucket] case final bucketRooms?) ...[
            _GroupHeader(label: bucket.label),
            _buildBlock(context, bucketRooms),
          ],
      ],
    );
  }

  DateTime? _activityFor(Room room) =>
      roomActivity[(serverId: serverId, roomId: room.id)];

  /// Renders [rooms] in the active view mode (no grouping).
  Widget _buildBlock(BuildContext context, List<Room> rooms) {
    return switch (viewMode) {
      LobbyViewMode.list => Padding(
          // Match the section heading and the grid's s4 gutter so list rows
          // align with everything around them instead of hugging the edge.
          padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s4),
          child: Column(
            children: [
              for (final room in rooms)
                RoomCard(
                  room: room,
                  activityTime: _activityFor(room),
                  onTap: () => onRoomTap(serverId, room.id),
                  onInfoTap: () => onInfoTap(serverId, room.id),
                ),
            ],
          ),
        ),
      LobbyViewMode.grid => _RoomGrid(
          serverId: serverId,
          rooms: rooms,
          activityFor: _activityFor,
          onRoomTap: onRoomTap,
          onInfoTap: onInfoTap,
        ),
    };
  }

  /// Orders rooms by most-recent-thread activity (descending) when that sort
  /// is active. Rooms without a known timestamp — none fetched, no threads,
  /// or a failed lookup — keep their original relative order at the end. Ties
  /// break by original index so equal timestamps stay in their input order
  /// (`List.sort` is not guaranteed stable). Does not mutate the input list.
  List<Room> _applySort(List<Room> rooms) {
    if (sortMode != LobbySortMode.recentActivity) return rooms;
    final dated = <(Room, DateTime, int)>[];
    final undated = <Room>[];
    for (var i = 0; i < rooms.length; i++) {
      final time = _activityFor(rooms[i]);
      if (time != null) {
        dated.add((rooms[i], time, i));
      } else {
        undated.add(rooms[i]);
      }
    }
    dated.sort((a, b) {
      final byTime = b.$2.compareTo(a.$2);
      return byTime != 0 ? byTime : a.$3.compareTo(b.$3);
    });
    return [...dated.map((e) => e.$1), ...undated];
  }
}

/// Responsive grid of [RoomGridCard]s for a single server's rooms.
///
/// Lives inside the outer room `ListView`, so it lays the cards out as a
/// [Column] of [IntrinsicHeight] rows rather than a nested scrollable grid.
/// Each row stretches its cells with [Expanded] so cards in a row share the
/// tallest one's height. Only the column count comes from [roomGridColumns].
class _RoomGrid extends StatelessWidget {
  const _RoomGrid({
    required this.serverId,
    required this.rooms,
    required this.activityFor,
    required this.onRoomTap,
    required this.onInfoTap,
  });

  final String serverId;
  final List<Room> rooms;
  final DateTime? Function(Room) activityFor;
  final void Function(String serverId, String roomId) onRoomTap;
  final void Function(String serverId, String roomId) onInfoTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const spacing = SoliplexSpacing.s3;
          final columns = roomGridColumns(constraints.maxWidth);
          // Lay the cards out as explicit rows rather than a Wrap so each row
          // can be wrapped in an IntrinsicHeight: cards in the same row then
          // share the tallest one's height and read as a regular grid,
          // instead of each sizing to its own text. Cells stretch and the
          // last row is padded with empty slots to keep widths uniform.
          final rows = <Widget>[];
          for (var start = 0; start < rooms.length; start += columns) {
            final end =
                start + columns < rooms.length ? start + columns : rooms.length;
            final rowRooms = rooms.sublist(start, end);
            rows.add(
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < columns; i++) ...[
                      if (i > 0) const SizedBox(width: spacing),
                      Expanded(
                        child: i < rowRooms.length
                            ? RoomGridCard(
                                room: rowRooms[i],
                                activityTime: activityFor(rowRooms[i]),
                                onTap: () =>
                                    onRoomTap(serverId, rowRooms[i].id),
                                onInfoTap: () =>
                                    onInfoTap(serverId, rowRooms[i].id),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }
          return Column(
            children: [
              for (var r = 0; r < rows.length; r++) ...[
                if (r > 0) const SizedBox(height: spacing),
                rows[r],
              ],
            ],
          );
        },
      ),
    );
  }
}

/// A recency-bucket section header: a muted label with a trailing rule, used
/// to separate "Today", "Yesterday", ... groups when sorting by activity.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(SoliplexSpacing.s4, SoliplexSpacing.s3,
          SoliplexSpacing.s4, SoliplexSpacing.s2),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: SoliplexSpacing.s3),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}
