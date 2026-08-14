import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
// Only 'ThreadInfo': the barrel also exports ag_ui's 'State', which would
// collide with Flutter's in a widget file.
import 'package:soliplex_agent/soliplex_agent.dart' show ThreadInfo;
import 'package:soliplex_design/soliplex_design.dart';

import '../../../shared/relative_time.dart';
import '../global_threads_state.dart';
import '../lobby_tab.dart';

/// One row of the aggregated listing: either a room heading or a thread.
///
/// The backend returns each room's threads contiguously, so flattening is a
/// single pass that emits a heading whenever the room changes — no grouping
/// or sorting happens here, which is what keeps the list correct while it
/// is still being paged in.
sealed class _Row {
  const _Row();
}

final class _RoomHeadingRow extends _Row {
  const _RoomHeadingRow(this.roomId);
  final String roomId;
}

final class _ThreadRow extends _Row {
  const _ThreadRow(this.thread);
  final ThreadInfo thread;
}

/// A trailing row shown while the next page is in flight.
final class _LoadingRow extends _Row {
  const _LoadingRow();
}

List<_Row> _flatten(List<ThreadInfo> threads, {required bool loadingMore}) {
  final rows = <_Row>[];
  String? currentRoom;
  for (final thread in threads) {
    if (thread.roomId != currentRoom) {
      currentRoom = thread.roomId;
      rows.add(_RoomHeadingRow(currentRoom));
    }
    rows.add(_ThreadRow(thread));
  }
  if (loadingMore) rows.add(const _LoadingRow());
  return rows;
}

/// Everything the lobby needs to render and drive its tab strip.
///
/// Bundled rather than passed as loose parameters because both the wide
/// and narrow layouts forward the lobby's props verbatim, and each already
/// carries around twenty.
@immutable
class LobbyThreadsSection {
  const LobbyThreadsSection({
    required this.activeTab,
    required this.onTabChanged,
    required this.state,
    required this.onThreadTap,
  });

  final LobbyTab activeTab;
  final ValueChanged<LobbyTab> onTabChanged;
  final GlobalThreadsState state;

  /// Invoked with the room and thread to open.
  final void Function(String roomId, String threadId) onThreadTap;
}

/// The lobby's rooms/threads tab strip.
///
/// Owns its own [TabController] and keeps it in step with [activeTab],
/// which is persisted outside the widget tree. Holding the controller here
/// rather than in the screen keeps the two layouts from having to thread a
/// controller through their (already long) parameter lists.
class LobbyTabBar extends StatefulWidget {
  const LobbyTabBar({
    super.key,
    required this.activeTab,
    required this.onTabChanged,
  });

  final LobbyTab activeTab;
  final ValueChanged<LobbyTab> onTabChanged;

  @override
  State<LobbyTabBar> createState() => _LobbyTabBarState();
}

class _LobbyTabBarState extends State<LobbyTabBar>
    with SingleTickerProviderStateMixin {
  late final TabController _controller = TabController(
    length: LobbyTab.values.length,
    vsync: this,
    initialIndex: widget.activeTab.index,
  )..addListener(_onControllerChanged);

  @override
  void didUpdateWidget(LobbyTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The tab can change from outside the strip (the persisted preference
    // resolving at launch). Mirror it without re-notifying, or the two
    // would bounce updates off each other.
    if (widget.activeTab.index != _controller.index) {
      _controller.index = widget.activeTab.index;
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    // Fires twice per swipe (start and settle); only the settled index is
    // worth persisting.
    if (_controller.indexIsChanging) return;
    final tab = LobbyTab.values[_controller.index];
    if (tab != widget.activeTab) widget.onTabChanged(tab);
  }

  @override
  Widget build(BuildContext context) {
    return TabBar(
      controller: _controller,
      tabs: const [
        Tab(text: 'Rooms'),
        Tab(text: 'Threads'),
      ],
    );
  }
}

/// The lobby's aggregated thread listing for the selected server.
///
/// Threads from every room the user can see, in one lazily-paged list,
/// divided by room. Deliberately carries no label chips — the room and
/// thread lists stay uncluttered.
class GlobalThreadsView extends StatefulWidget {
  const GlobalThreadsView({
    super.key,
    required this.state,
    required this.roomNames,
    required this.onThreadTap,
  });

  final GlobalThreadsState state;

  /// Display names for the selected server's rooms, keyed by room id. A
  /// room missing here falls back to its id rather than rendering blank.
  final Map<String, String> roomNames;

  final void Function(String roomId, String threadId) onThreadTap;

  @override
  State<GlobalThreadsView> createState() => _GlobalThreadsViewState();
}

class _GlobalThreadsViewState extends State<GlobalThreadsView> {
  final ScrollController _controller = ScrollController();

  /// How close to the bottom, in pixels, triggers the next page. Roughly a
  /// screenful, so the page is usually resolved before the user reaches it.
  static const double _loadMoreThreshold = 600;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    if (position.extentAfter > _loadMoreThreshold) return;
    // Firing repeatedly while near the bottom is fine: loadMore declines
    // when a page is already in flight or the last one has arrived.
    widget.state.loadMore();
  }

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final threads = widget.state.threads.value;
      return switch (threads) {
        GlobalThreadsLoading() => const Center(
            child: CircularProgressIndicator(),
          ),
        GlobalThreadsUnsupported() => const _ThreadsMessage(
            icon: Icons.update,
            title: 'Threads need a newer server',
            detail: 'This server cannot list threads across rooms yet. '
                'Open a room to see its threads.',
          ),
        GlobalThreadsFailed() => _ThreadsMessage(
            icon: Icons.error_outline,
            title: 'Could not load threads',
            detail: '${threads.error}',
            onRetry: widget.state.refresh,
          ),
        GlobalThreadsLoaded() => _buildList(context, threads),
      };
    });
  }

  Widget _buildList(BuildContext context, GlobalThreadsLoaded loaded) {
    if (loaded.threads.isEmpty) {
      return const _ThreadsMessage(
        icon: Icons.forum_outlined,
        title: 'No threads yet',
        detail: 'Threads you start in any room show up here.',
      );
    }

    final rows = _flatten(loaded.threads, loadingMore: loaded.loadingMore);

    return RefreshIndicator(
      onRefresh: widget.state.refresh,
      child: ListView.builder(
        controller: _controller,
        padding: const EdgeInsets.only(bottom: SoliplexSpacing.s4),
        itemCount: rows.length,
        itemBuilder: (context, index) => switch (rows[index]) {
          _RoomHeadingRow(:final roomId) => _RoomHeading(
              name: widget.roomNames[roomId] ?? roomId,
            ),
          _ThreadRow(:final thread) => _ThreadListTile(
              thread: thread,
              onTap: () => widget.onThreadTap(thread.roomId, thread.id),
            ),
          _LoadingRow() => const Padding(
              padding: EdgeInsets.all(SoliplexSpacing.s4),
              child: Center(child: CircularProgressIndicator()),
            ),
        },
      ),
    );
  }
}

/// A room's name, dividing its block of threads from the previous room's.
class _RoomHeading extends StatelessWidget {
  const _RoomHeading({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SoliplexSpacing.s4,
        SoliplexSpacing.s4,
        SoliplexSpacing.s4,
        SoliplexSpacing.s2,
      ),
      // The rule sits under the name rather than beside it, so every
      // divider spans the same width. Running it inline would leave it
      // whatever the room name did not use, making a long-named room look
      // like a shorter section break than a short-named one.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            name,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: SoliplexSpacing.s2),
          Divider(
            height: 1,
            thickness: 1,
            color: theme.colorScheme.outlineVariant,
          ),
        ],
      ),
    );
  }
}

class _ThreadListTile extends StatelessWidget {
  const _ThreadListTile({required this.thread, required this.onTap});

  final ThreadInfo thread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // A thread with no name has never been titled; show the same
    // placeholder the room sidebar uses rather than an empty row.
    final title = thread.hasName ? thread.name : 'New Thread';
    final stamp = thread.lastActivity ?? thread.createdAt;
    return ListTile(
      dense: true,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(formatRelativeTime(stamp)),
      onTap: onTap,
    );
  }
}

/// A centered icon/title/detail block for the empty, error and
/// unsupported-server states.
class _ThreadsMessage extends StatelessWidget {
  const _ThreadsMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SoliplexSpacing.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: SoliplexSpacing.s3),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: SoliplexSpacing.s2),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: SoliplexSpacing.s4),
              SoliplexButton.outlined(
                onPressed: () => onRetry!(),
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
