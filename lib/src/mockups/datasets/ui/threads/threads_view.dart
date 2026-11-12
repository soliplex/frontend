import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show ThreadInfo;
import 'package:soliplex_client/soliplex_client.dart' show ThreadLabel;
import 'package:soliplex_design/soliplex_design.dart';

import '../../../../modules/lobby/global_threads_state.dart';
import '../../../../modules/lobby/ui/global_threads_view.dart'
    show ThreadRowAction;
import '../../../../shared/label_chip.dart';
import '../../../../shared/relative_time.dart';
import '../../../../stores/labels_state.dart';
import '../../../chat/static_backend.dart';
import 'thread_query.dart';
import 'thread_search_field.dart';

// MOCKUP: a copy of the lobby's `GlobalThreadsView` for a listing that mixes
// threads in rooms with conversations outside them. It adds a scope filter,
// `in:room` and `@no-label` search, grouping by room, and a trailing icon
// saying which kind each row is. `@no-label` is the app's own `unlabeled`
// filter; the room filter goes to the static backend's [roomFilter],
// standing in for a `room_ids` parameter on `GET /v1/agui/threads`.

/// Which threads the listing covers.
enum ThreadScope {
  all('All'),
  inRooms('In rooms'),
  noRoom('No room');

  const ThreadScope(this.label);

  final String label;
}

class ThreadsView extends StatefulWidget {
  const ThreadsView({
    super.key,
    required this.state,
    required this.labels,
    required this.api,
    required this.roomNames,
    required this.roomlessId,
    required this.onThreadTap,
    required this.onThreadAction,
  });

  final GlobalThreadsState state;
  final LabelsState labels;
  final StaticSoliplexApi api;

  /// Display names of the real rooms, keyed by id.
  final Map<String, String> roomNames;

  /// The id that holds conversations outside rooms.
  final String roomlessId;

  final void Function(String roomId, String threadId) onThreadTap;
  final void Function(ThreadInfo thread, ThreadRowAction action) onThreadAction;

  @override
  State<ThreadsView> createState() => _ThreadsViewState();
}

class _ThreadsViewState extends State<ThreadsView> {
  final ScrollController _controller = ScrollController();
  static const double _loadMoreThreshold = 600;

  final _search = GlobalKey<ThreadSearchFieldState>();
  ThreadScope _scope = ThreadScope.all;
  bool _grouped = false;
  ThreadQuery _query = ThreadQuery.empty;

  /// `@label` and `in:room` names that match nothing, as typed.
  List<String> _unknown = const [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    widget.api.roomFilter = null;
  }

  @override
  void dispose() {
    widget.api.roomFilter = null;
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    if (_controller.position.extentAfter > _loadMoreThreshold) return;
    widget.state.loadMore();
  }

  bool get _filtered =>
      widget.state.isFiltered ||
      _scope != ThreadScope.all ||
      _query.roomNames.isNotEmpty;

  /// Applies the scope and the query: labels and text through the state's
  /// own filter, rooms through the backend's.
  void _apply() {
    final catalogue = {
      for (final label in widget.labels.current) label.name.toLowerCase(): label
    };
    final rooms = {
      for (final MapEntry(:key, :value) in widget.roomNames.entries)
        value.toLowerCase(): key,
      noRoomToken: widget.roomlessId,
    };

    final unknown = [
      for (final name in _query.labelNames)
        if (name != noLabelToken && !catalogue.containsKey(name))
          formatToken(TokenKind.label, name),
      for (final name in _query.roomNames)
        if (!rooms.containsKey(name)) formatToken(TokenKind.room, name),
    ];
    setState(() => _unknown = unknown);
    if (unknown.isNotEmpty) return;

    final named = _query.roomNames.isEmpty
        ? null
        : {for (final name in _query.roomNames) rooms[name]!};
    final scoped = switch (_scope) {
      ThreadScope.all => null,
      ThreadScope.inRooms => widget.roomNames.keys.toSet(),
      ThreadScope.noRoom => {widget.roomlessId},
    };
    final filter = named == null
        ? scoped
        : scoped == null
            ? named
            : named.intersection(scoped);

    final roomsChanged = !_sameSet(filter, widget.api.roomFilter);
    widget.api.roomFilter = filter;
    widget.state.setFilter(
      labelIds: [
        for (final name in _query.labelNames)
          if (name != noLabelToken) catalogue[name]!.id,
      ],
      unlabeled: _query.labelNames.contains(noLabelToken),
      query: _query.text,
    );
    if (roomsChanged) widget.state.refresh();
  }

  static bool _sameSet(Set<String>? a, Set<String>? b) => a == null || b == null
      ? a == b
      : a.length == b.length && a.containsAll(b);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SoliplexSpacing.s4,
            SoliplexSpacing.s2,
            SoliplexSpacing.s4,
            SoliplexSpacing.s2,
          ),
          child: Watch(
            (context) => ThreadSearchField(
              key: _search,
              labels: widget.labels.current,
              roomNames: widget.roomNames.values.toList(),
              onChanged: (query) {
                _query = query;
                _apply();
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SoliplexSpacing.s4,
            0,
            SoliplexSpacing.s4,
            SoliplexSpacing.s2,
          ),
          // Two sets of chips that do different things: which threads show,
          // and how they are laid out. Each is named, and a rule keeps them
          // apart, so "Room" is not read as a fourth scope.
          child: Wrap(
            spacing: SoliplexSpacing.s2,
            runSpacing: SoliplexSpacing.s2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _ChipGroup(
                title: 'Show',
                chips: [
                  for (final scope in ThreadScope.values)
                    SoliplexChip.filter(
                      label: Text(scope.label),
                      icon: scope == ThreadScope.all
                          ? null
                          : RoomLinkIcon(
                              roomless: scope == ThreadScope.noRoom,
                            ),
                      selected: _scope == scope,
                      onSelected: (_) {
                        _scope = scope;
                        _apply();
                      },
                    ),
                ],
              ),
              const SizedBox(
                height: SoliplexSpacing.s6,
                child: VerticalDivider(width: SoliplexSpacing.s4),
              ),
              _ChipGroup(
                title: 'Group by',
                chips: [
                  SoliplexChip.filter(
                    label: const Text('Room'),
                    icon: const Icon(Icons.view_agenda_outlined, size: 18),
                    selected: _grouped,
                    onSelected: (value) => setState(() => _grouped = value),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_unknown.isNotEmpty) {
      return _ThreadsMessage(
        icon: Icons.search_off,
        title: 'Nothing by that name',
        detail: '${_unknown.join(', ')} matches no label or room here.',
      );
    }

    return Watch((context) {
      final threads = widget.state.threads.value;
      return switch (threads) {
        GlobalThreadsLoading() =>
          const Center(child: CircularProgressIndicator()),
        GlobalThreadsUnsupported() => const _ThreadsMessage(
            icon: Icons.update,
            title: 'Threads need a newer server',
            detail: 'This server cannot list threads across rooms yet.',
          ),
        GlobalThreadsFailed() => _ThreadsMessage(
            icon: Icons.error_outline,
            title: 'Could not load threads',
            detail: '${threads.error}',
            onRetry: widget.state.refresh,
          ),
        GlobalThreadsSignedOut(:final expired) => _ThreadsMessage(
            icon: Icons.lock_outline,
            title: expired ? 'Session expired' : 'Signed out',
            detail: expired
                ? 'Sign in again to view threads on this server.'
                : 'Sign in to view threads on this server.',
          ),
        GlobalThreadsLoaded() => _buildList(context, threads),
      };
    });
  }

  String _roomName(String roomId) => roomId == widget.roomlessId
      ? 'No room'
      : widget.roomNames[roomId] ?? roomId;

  Widget _buildList(BuildContext context, GlobalThreadsLoaded loaded) {
    if (loaded.threads.isEmpty) {
      return _filtered
          ? const _ThreadsMessage(
              icon: Icons.search_off,
              title: 'No matching threads',
              detail: 'Try a different name, fewer labels, or another scope.',
            )
          : const _ThreadsMessage(
              icon: Icons.forum_outlined,
              title: 'No threads yet',
              detail: 'Threads and conversations you start show up here.',
            );
    }

    // Grouped rows keep the activity order within each room. Only the pages
    // already loaded are grouped, so a room's section can grow on scroll.
    final rows = <Object>[];
    if (_grouped) {
      final byRoom = <String, List<ThreadInfo>>{};
      for (final thread in loaded.threads) {
        (byRoom[thread.roomId] ??= []).add(thread);
      }
      final order = [
        if (byRoom.containsKey(widget.roomlessId)) widget.roomlessId,
        for (final id in byRoom.keys)
          if (id != widget.roomlessId) id,
      ];
      for (final id in order) {
        rows
          ..add(id)
          ..addAll(byRoom[id]!);
      }
    } else {
      rows.addAll(loaded.threads);
    }

    return RefreshIndicator(
      onRefresh: widget.state.refresh,
      child: ListView.builder(
        controller: _controller,
        padding: const EdgeInsets.only(bottom: SoliplexSpacing.s4),
        itemCount: rows.length + (loaded.loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == rows.length) {
            return const Padding(
              padding: EdgeInsets.all(SoliplexSpacing.s4),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final row = rows[index];
          if (row is String) {
            return _GroupHeader(
              name: _roomName(row),
              roomless: row == widget.roomlessId,
            );
          }
          final thread = row as ThreadInfo;
          return _ThreadListTile(
            thread: thread,
            roomName: _roomName(thread.roomId),
            roomless: thread.roomId == widget.roomlessId,
            showRoom: !_grouped,
            onLabelTap: (label) =>
                _search.currentState?.addToken(TokenKind.label, label.name),
            onTap: () => widget.onThreadTap(thread.roomId, thread.id),
            onAction: (action) => widget.onThreadAction(thread, action),
          );
        },
      ),
    );
  }
}

/// A small caption and the chips it names, wrapping together.
class _ChipGroup extends StatelessWidget {
  const _ChipGroup({required this.title, required this.chips});

  final String title;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: SoliplexSpacing.s2,
      runSpacing: SoliplexSpacing.s2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          title,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        ...chips,
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.name, required this.roomless});

  final String name;
  final bool roomless;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SoliplexSpacing.s4,
        SoliplexSpacing.s4,
        SoliplexSpacing.s4,
        SoliplexSpacing.s1,
      ),
      child: Row(
        children: [
          RoomLinkIcon(roomless: roomless),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadListTile extends StatefulWidget {
  const _ThreadListTile({
    required this.thread,
    required this.roomName,
    required this.roomless,
    required this.showRoom,
    required this.onLabelTap,
    required this.onTap,
    required this.onAction,
  });

  final ThreadInfo thread;
  final String roomName;
  final bool roomless;

  /// Whether the subtitle names the room; a grouped list says it once in
  /// the section header instead.
  final bool showRoom;

  /// Filters the listing by a label tapped on the row.
  final ValueChanged<ThreadLabel> onLabelTap;

  final VoidCallback onTap;
  final void Function(ThreadRowAction action) onAction;

  @override
  State<_ThreadListTile> createState() => _ThreadListTileState();
}

class _ThreadListTileState extends State<_ThreadListTile> {
  bool _hovered = false;
  bool _menuOpen = false;

  static bool get _isDesktop => switch (defaultTargetPlatform) {
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux =>
          true,
        _ => false,
      };

  @override
  Widget build(BuildContext context) {
    final thread = widget.thread;
    final title = thread.hasName ? thread.name : 'New Thread';
    final when = formatRelativeTime(thread.lastActivity ?? thread.createdAt);
    final showMenu = _hovered || _menuOpen || !_isDesktop;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: ListTile(
        dense: true,
        title: _buildTitle(context, title),
        subtitle: Text(
          widget.showRoom ? '${widget.roomName} · $when' : when,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: widget.onTap,
        // The menu opens to the left of the icon, so the icon keeps its
        // column whether or not the row is hovered.
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showMenu) ...[
              _buildMenu(context),
              const SizedBox(width: SoliplexSpacing.s2),
            ],
            RoomLinkIcon(
              roomless: widget.roomless,
              tooltip:
                  widget.roomless ? 'Not in a room' : 'In ${widget.roomName}',
            ),
          ],
        ),
      ),
    );
  }

  /// How many labels a row shows before "+N": enough for most threads,
  /// few enough that one heavily labelled thread keeps an ordinary height.
  static const _maxLabels = 3;

  /// The title with the thread's labels after it, wrapping under it when
  /// the row runs out of width, as GitHub lists issues.
  Widget _buildTitle(BuildContext context, String title) {
    final labels = widget.thread.labels;
    final text = Text(title, maxLines: 1, overflow: TextOverflow.ellipsis);
    if (labels.isEmpty) return text;

    final theme = Theme.of(context);
    final hidden = labels.length - _maxLabels;
    return Theme(
      // Compact chips, so a labelled row is not twice the height of one
      // without labels.
      data: theme.copyWith(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        chipTheme: theme.chipTheme.copyWith(
          labelStyle: theme.textTheme.labelSmall,
          padding: EdgeInsets.zero,
          labelPadding: const EdgeInsets.symmetric(
            horizontal: SoliplexSpacing.s1,
          ),
        ),
      ),
      child: Wrap(
        spacing: SoliplexSpacing.s2,
        runSpacing: SoliplexSpacing.s1,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          text,
          for (final label in labels.take(_maxLabels))
            Tooltip(
              message: 'Show threads labelled ${label.name}',
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => widget.onLabelTap(label),
                  child: LabelChip(label: label),
                ),
              ),
            ),
          if (hidden > 0)
            Tooltip(
              message: labels.skip(_maxLabels).map((l) => l.name).join(', '),
              child: Text(
                '+$hidden',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMenu(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<ThreadRowAction>(
      icon: Icon(
        Icons.more_vert,
        size: 18,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      tooltip: 'Thread options',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onOpened: () => setState(() => _menuOpen = true),
      onCanceled: () => setState(() => _menuOpen = false),
      onSelected: (action) {
        setState(() => _menuOpen = false);
        widget.onAction(action);
      },
      itemBuilder: (context) => [
        for (final (action, label, icon) in const [
          (ThreadRowAction.properties, 'Properties', Icons.tune),
          (ThreadRowAction.rename, 'Rename', Icons.edit_outlined),
        ])
          PopupMenuItem(
            value: action,
            child: Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: SoliplexSpacing.s3),
                Text(label),
              ],
            ),
          ),
        PopupMenuItem(
          value: ThreadRowAction.delete,
          child: Row(
            children: [
              Icon(
                Icons.delete_outline,
                size: 18,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: SoliplexSpacing.s3),
              Text(
                'Delete',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

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
