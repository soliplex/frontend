import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
// Only 'ThreadInfo': the barrel also exports ag_ui's 'State', which would
// collide with Flutter's in a widget file.
import 'package:soliplex_agent/soliplex_agent.dart' show ThreadInfo;
import 'package:soliplex_design/soliplex_design.dart';

import '../../../shared/relative_time.dart';
import '../global_threads_state.dart';
import '../../../stores/labels_state.dart';
import '../lobby_tab.dart';
import '../thread_query.dart';
import 'load_failure.dart';
import 'thread_search_field.dart';

/// Everything the lobby needs to render and drive its tab strip.
///
/// Bundled rather than passed as loose parameters because both the wide
/// and narrow layouts forward the lobby's props verbatim, and each already
/// carries around twenty.
@immutable
class LobbyTabsSection {
  const LobbyTabsSection({
    required this.tabs,
    required this.activeTab,
    required this.onTabChanged,
    required this.threads,
    required this.labels,
    required this.onThreadTap,
    required this.onThreadAction,
    required this.onSignIn,
    this.selectedLabelId,
  });

  /// The tabs this user may see, in display order.
  ///
  /// Not every user gets every tab — the labels tab is administrators
  /// only — so this is the authority on both what the strip renders and
  /// what [activeTab] is allowed to be.
  final List<LobbyTab> tabs;

  final LobbyTab activeTab;
  final ValueChanged<LobbyTab> onTabChanged;
  final GlobalThreadsState threads;
  final LabelsState labels;

  /// Invoked with the room and thread to open.
  final void Function(String roomId, String threadId) onThreadTap;

  /// Invoked with the thread and the menu entry chosen on it.
  final void Function(ThreadInfo thread, ThreadRowAction action) onThreadAction;

  /// Routes to the selected server's sign-in, for a listing that can't load
  /// until the user signs in again.
  final VoidCallback onSignIn;

  /// A label to highlight on the labels tab, after a thread's properties
  /// jumped there to edit it.
  final int? selectedLabelId;

  /// Where [activeTab] sits among [tabs].
  ///
  /// Falls back to zero for a tab this user cannot see — a persisted
  /// preference for the labels tab outliving an administrator's access,
  /// say — which would otherwise index past the end of the strip.
  int get activeIndex {
    final index = tabs.indexOf(activeTab);
    return index < 0 ? 0 : index;
  }
}

/// The lobby's tab strip.
///
/// Owns its own [TabController] and keeps it in step with the active tab,
/// which is persisted outside the widget tree. Holding the controller here
/// rather than in the screen keeps the two layouts from having to thread a
/// controller through their (already long) parameter lists.
class LobbyTabBar extends StatefulWidget {
  const LobbyTabBar({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.onTabChanged,
  });

  final List<LobbyTab> tabs;
  final int activeIndex;
  final ValueChanged<LobbyTab> onTabChanged;

  @override
  State<LobbyTabBar> createState() => _LobbyTabBarState();
}

class _LobbyTabBarState extends State<LobbyTabBar>
    with TickerProviderStateMixin {
  late TabController _controller = _newController();

  TabController _newController() => TabController(
        length: widget.tabs.length,
        vsync: this,
        initialIndex: widget.activeIndex,
      )..addListener(_onControllerChanged);

  @override
  void didUpdateWidget(LobbyTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);

    // A TabController's length is fixed at construction, so a change in
    // how many tabs this user may see means a new controller — which is
    // also why this mixes in TickerProviderStateMixin rather than the
    // single-ticker variant.
    if (widget.tabs.length != _controller.length) {
      _disposeController();
      _controller = _newController();
      return;
    }

    // The tab can change from outside the strip (the persisted preference
    // resolving at launch). Mirror it without re-notifying, or the two
    // would bounce updates off each other.
    if (widget.activeIndex != _controller.index) {
      _controller.index = widget.activeIndex;
    }
  }

  void _disposeController() {
    _controller
      ..removeListener(_onControllerChanged)
      ..dispose();
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _onControllerChanged() {
    // Fires twice per swipe (start and settle); only the settled index is
    // worth persisting.
    if (_controller.indexIsChanging) return;
    if (_controller.index >= widget.tabs.length) return;
    final tab = widget.tabs[_controller.index];
    widget.onTabChanged(tab);
  }

  @override
  Widget build(BuildContext context) {
    return TabBar(
      controller: _controller,
      tabs: [
        for (final tab in widget.tabs) Tab(text: _tabLabel(tab)),
      ],
    );
  }
}

String _tabLabel(LobbyTab tab) => switch (tab) {
      LobbyTab.rooms => 'Rooms',
      LobbyTab.threads => 'Threads',
      LobbyTab.labels => 'Labels',
    };

/// The lobby's aggregated thread listing for the selected server.
///
/// Threads from every room the user can see, in one lazily-paged list,
/// most recently active first. Each row names its room, so a thread can be
/// found without first recalling where it lives. Deliberately carries no
/// label chips — the room and thread lists stay uncluttered.
class GlobalThreadsView extends StatefulWidget {
  const GlobalThreadsView({
    super.key,
    required this.state,
    required this.labels,
    required this.roomNames,
    required this.onThreadTap,
    required this.onThreadAction,
    required this.onSignIn,
  });

  final GlobalThreadsState state;

  /// The server's catalogue, for the `@label` autocomplete.
  final LabelsState labels;

  /// Display names for the selected server's rooms, keyed by room id. A
  /// room missing here falls back to its id rather than rendering blank.
  final Map<String, String> roomNames;

  final void Function(String roomId, String threadId) onThreadTap;

  /// Invoked with the thread and the menu entry chosen on it.
  final void Function(ThreadInfo thread, ThreadRowAction action) onThreadAction;

  /// Routes to the server's sign-in.
  final VoidCallback onSignIn;

  @override
  State<GlobalThreadsView> createState() => _GlobalThreadsViewState();
}

class _GlobalThreadsViewState extends State<GlobalThreadsView> {
  // Starts where the user left off: the state outlives this view.
  late final ScrollController _controller =
      ScrollController(initialScrollOffset: widget.state.scrollOffset);

  /// How close to the bottom, in pixels, triggers the next page. Roughly a
  /// screenful, so the page is usually resolved before the user reaches it.
  static const double _loadMoreThreshold = 600;

  late final void Function() _unwatchCatalogue;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    // A query that named labels before the catalogue arrived, or while
    // it was failing, is resolved once it loads -- for this view's server
    // only: on a switch the new server's catalogue can land before this
    // view is replaced, and its query must not follow the user there.
    final serverId = widget.state.serverId;
    _unwatchCatalogue = widget.labels.labels.subscribe((labels) {
      final query = _lastQuery;
      if (labels is! LabelsLoaded || query == null || !mounted) return;
      if (query.labelNames.isEmpty) return;
      if (widget.state.serverId != serverId) return;
      _onQueryChanged(query);
    });
  }

  @override
  void dispose() {
    _unwatchCatalogue();
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    widget.state.scrollOffset = _controller.offset;
    _loadMoreIfNearEnd();
  }

  /// Asks for the next page once the end of the list is in reach.
  ///
  /// Runs on scroll and after every frame that shows rows: a page too
  /// short to fill the viewport can't be scrolled, so waiting for a scroll
  /// would leave the rest of the listing unrequested, with nothing on
  /// screen to say there is more.
  void _loadMoreIfNearEnd() {
    if (!mounted || !_controller.hasClients) return;
    final threads = widget.state.threads.value;
    // After a failure the user retries; asking again on every scroll
    // would hammer a server that just refused.
    if (threads is! GlobalThreadsLoaded || threads.loadMoreError != null) {
      return;
    }
    if (_controller.position.extentAfter > _loadMoreThreshold) return;
    // Firing repeatedly while near the bottom is fine: loadMore declines
    // when a page is already in flight or the last one has arrived.
    widget.state.loadMore();
  }

  /// Label names typed as `@name` that match nothing in the catalogue.
  ///
  /// Held rather than sent, because an unresolvable name cannot be
  /// expressed as a filter: an empty `labelIds` means *unfiltered*, so
  /// dropping the name would silently widen the listing to everything —
  /// the opposite of what was asked for.
  List<String> _unknownLabels = const [];

  /// The query last typed, kept so it can be resolved again when the
  /// catalogue it names labels from arrives.
  ThreadQuery? _lastQuery;

  void _onQueryChanged(ThreadQuery query) {
    _lastQuery = query;
    final labels = widget.labels.labels.value;
    if (query.labelNames.isNotEmpty && labels is! LabelsLoaded) {
      // Can't tell a typo from a label not loaded yet; the body says
      // which, and this runs again when the catalogue loads.
      setState(() => _unknownLabels = const []);
      return;
    }
    final catalogue = {
      for (final label in widget.labels.catalogue.value)
        label.name.toLowerCase(): label,
    };

    final resolved = <int>[];
    final unknown = <String>[];
    for (final name in query.labelNames) {
      final label = catalogue[name];
      if (label == null) {
        unknown.add(name);
      } else {
        resolved.add(label.id);
      }
    }

    setState(() => _unknownLabels = unknown);
    if (unknown.isNotEmpty) return;

    widget.state.setFilter(
      labelIds: resolved,
      unlabeled: query.unlabeled,
      query: query.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
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
              labels: widget.labels.catalogue.value,
              onChanged: _onQueryChanged,
              initialText: widget.state.searchText,
              onTextChanged: (text) => widget.state.searchText = text,
            ),
          ),
        ),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_lastQuery?.labelNames.isNotEmpty ?? false) {
      final pending = Watch((context) {
        return switch (widget.labels.labels.value) {
          LabelsLoading() => const Center(child: CircularProgressIndicator()),
          LabelsFailed(:final error) => () {
              final failure = describeLoadFailure(error, what: 'labels');
              return _ThreadsMessage(
                icon: Icons.label_off_outlined,
                title: "Couldn't load this server's labels",
                detail: '${failure.detail} '
                    'Search by name, or try again.',
                onRetry: failure.retryable ? widget.labels.refresh : null,
              );
            }(),
          LabelsUnsupported() => const _ThreadsMessage(
              icon: Icons.label_off_outlined,
              title: 'This server has no labels',
              detail: 'Search by name instead.',
            ),
          LabelsLoaded() => const SizedBox.shrink(),
        };
      });
      if (widget.labels.labels.value is! LabelsLoaded) return pending;
    }

    if (_unknownLabels.isNotEmpty) {
      final names = _unknownLabels.map((name) => '@$name').join(', ');
      return _ThreadsMessage(
        icon: Icons.label_off_outlined,
        title: 'No such label',
        detail: '$names does not match any label on this server.',
      );
    }

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
        GlobalThreadsFailed(:final error) => () {
            final failure = describeLoadFailure(error, what: 'threads');
            return _ThreadsMessage(
              icon: Icons.error_outline,
              title: 'Could not load threads',
              detail: failure.detail,
              onRetry: failure.retryable ? widget.state.refresh : null,
            );
          }(),
        GlobalThreadsSignedOut(:final expired) => _ThreadsMessage(
            icon: Icons.lock_outline,
            title: expired ? 'Session expired' : 'Signed out',
            detail: expired
                ? 'Sign in again to view threads on this server.'
                : 'Sign in to view threads on this server.',
            onSignIn: widget.onSignIn,
          ),
        GlobalThreadsLoaded() => _buildList(context, threads),
      };
    });
  }

  Widget _buildList(BuildContext context, GlobalThreadsLoaded loaded) {
    if (loaded.threads.isEmpty) {
      // "Nothing matched" and "you have nothing" are different answers,
      // and offering "threads you start show up here" to someone staring
      // at their own search would read as a bug.
      return widget.state.isFiltered
          ? const _ThreadsMessage(
              icon: Icons.search_off,
              title: 'No matching threads',
              detail: 'Try a different name, or fewer labels.',
            )
          : _ThreadsMessage(
              icon: Icons.forum_outlined,
              title: 'No threads yet',
              detail: 'Threads you start in any room show up here.',
              // A thread started on another device has no other way in.
              onRetry: widget.state.refresh,
              retryLabel: 'Refresh',
            );
    }

    final threads = loaded.threads;
    if (loaded.hasMore && !loaded.loadingMore) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadMoreIfNearEnd());
    }

    return RefreshIndicator(
      onRefresh: widget.state.refresh,
      child: ListView.builder(
        controller: _controller,
        padding: const EdgeInsets.only(bottom: SoliplexSpacing.s4),
        // One trailing row: the next page in flight, its failure, or the
        // end of the listing, so "that's everything" reads differently
        // from "the rest hasn't been asked for".
        itemCount: threads.length + 1,
        itemBuilder: (context, index) {
          if (index == threads.length) {
            if (loaded.loadMoreError != null) {
              return _LoadMoreFailedRow(onRetry: widget.state.loadMore);
            }
            if (!loaded.hasMore) return const _EndOfThreadsRow();
            return const Padding(
              padding: EdgeInsets.all(SoliplexSpacing.s4),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final thread = threads[index];
          return _ThreadListTile(
            thread: thread,
            roomName: widget.roomNames[thread.roomId] ?? thread.roomId,
            onTap: () => widget.onThreadTap(thread.roomId, thread.id),
            onAction: (action) => widget.onThreadAction(thread, action),
          );
        },
      ),
    );
  }
}

/// What the per-thread overflow menu offers.
enum ThreadRowAction { properties, rename, delete }

class _ThreadListTile extends StatefulWidget {
  const _ThreadListTile({
    required this.thread,
    required this.roomName,
    required this.onTap,
    required this.onAction,
  });

  final ThreadInfo thread;
  final String roomName;
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
    // A thread with no name has never been titled; show the same
    // placeholder the room sidebar uses rather than an empty row.
    final title = thread.hasName ? thread.name : 'New Thread';
    final stamp = thread.lastActivity ?? thread.createdAt;
    final showMenu = _hovered || _menuOpen || !_isDesktop;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: ListTile(
        dense: true,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${widget.roomName} · ${formatRelativeTime(stamp)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: widget.onTap,
        trailing: showMenu ? _buildMenu(context) : null,
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
      // Keeps the button mounted while the popup is open. Without it the
      // pointer leaving the row unmounts the button, and the popup's
      // completion callback short-circuits on '!mounted' — silently
      // dropping the selection. Learned the hard way in the room
      // sidebar's own menu; the same trap applies here.
      onOpened: () => setState(() => _menuOpen = true),
      onCanceled: () => setState(() => _menuOpen = false),
      onSelected: (action) {
        setState(() => _menuOpen = false);
        widget.onAction(action);
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: ThreadRowAction.properties,
          child: Row(
            children: [
              Icon(Icons.tune, size: 18),
              SizedBox(width: SoliplexSpacing.s3),
              Text('Properties'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: ThreadRowAction.rename,
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 18),
              SizedBox(width: SoliplexSpacing.s3),
              Text('Rename'),
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

/// A centered icon/title/detail block for the empty, error and
/// unsupported-server states.
/// Closes a listing whose last page has arrived.
class _EndOfThreadsRow extends StatelessWidget {
  const _EndOfThreadsRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(SoliplexSpacing.s4),
      child: Center(
        child: Text(
          'No more threads',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Stands in for the next page when it failed to load, below the rows
/// that did.
class _LoadMoreFailedRow extends StatelessWidget {
  const _LoadMoreFailedRow({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(SoliplexSpacing.s4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "Couldn't load more threads.",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: SoliplexSpacing.s2),
          SoliplexButton.text(
            onPressed: () => onRetry(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _ThreadsMessage extends StatelessWidget {
  const _ThreadsMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.onSignIn,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Future<void> Function()? onRetry;
  final String retryLabel;
  final VoidCallback? onSignIn;

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
                child: Text(retryLabel),
              ),
            ],
            if (onSignIn != null) ...[
              const SizedBox(height: SoliplexSpacing.s4),
              SoliplexButton.filled(
                onPressed: onSignIn,
                child: const Text('Sign in'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
