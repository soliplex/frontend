import 'dart:async';

import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;
import 'package:soliplex_client/soliplex_client.dart'
    show
        AuthException,
        NetworkException,
        NotFoundException,
        PermissionDeniedException,
        SoliplexApi;
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../stores/server_follower.dart';
import '../../stores/thread_properties.dart';
import '../auth/auth_tokens.dart' show ExpiredSession;
import '../auth/server_entry.dart';
import 'lobby_state.dart' show ApiResolver;

final Logger _logger =
    LogManager.instance.getLogger('soliplex.global_threads_state');

/// How many threads to pull per request.
const int kGlobalThreadsPageSize = 50;

/// The state of the aggregated cross-room thread listing.
sealed class GlobalThreads {
  const GlobalThreads();
}

/// Nothing is on screen yet: the first page is in flight, or no server
/// has been selected to ask.
final class GlobalThreadsLoading extends GlobalThreads {
  const GlobalThreadsLoading();
}

/// At least one page has arrived.
///
/// [loadingMore] distinguishes "appending the next page" from the initial
/// load, so the list can keep what it already shows and add a spinner row
/// rather than blanking.
final class GlobalThreadsLoaded extends GlobalThreads {
  GlobalThreadsLoaded({
    required List<ThreadInfo> threads,
    this.nextCursor,
    this.loadingMore = false,
    this.loadMoreError,
  }) : threads = List.unmodifiable(threads);

  final List<ThreadInfo> threads;

  /// The token for the page after the last one held; `null` once the last
  /// page has arrived.
  final String? nextCursor;

  final bool loadingMore;

  /// Why the last attempt at the next page failed, or `null`.
  ///
  /// A failed later page keeps the rows already held: the user is deep in
  /// the list, and a blip should cost them a retry, not their place.
  final Object? loadMoreError;

  bool get hasMore => nextCursor != null;
}

/// The listing could not be loaded.
final class GlobalThreadsFailed extends GlobalThreads {
  const GlobalThreadsFailed(this.error);
  final Object error;
}

/// The server can't serve the listing until the user signs in again.
///
/// Holds no rows: they belonged to whoever was signed in, and a sign-out
/// must not leave them on screen for the next person.
final class GlobalThreadsSignedOut extends GlobalThreads {
  const GlobalThreadsSignedOut({required this.expired});

  /// Whether the session expired, rather than the user signing out.
  final bool expired;
}

/// The server has no cross-room listing endpoint.
///
/// Distinct from [GlobalThreadsFailed] because it is not a fault to retry:
/// the server is simply older than this feature, and the UI should say so
/// instead of offering a retry that will always 404.
final class GlobalThreadsUnsupported extends GlobalThreads {
  const GlobalThreadsUnsupported();
}

/// Loads the user's threads across every room of one server, a page at a
/// time.
///
/// Scoped to a single server because each server is a separate backend:
/// aggregating across them would mean N independent paginated fetches with
/// no coherent global ordering. [follow] keeps it on the lobby's selection.
///
/// Outlives the lobby screen, so the pages a user has scrolled through, and
/// where they were, survive opening a thread and coming back.
class GlobalThreadsState {
  GlobalThreadsState({
    required ServerEntry? Function(String serverId) entryResolver,
    ApiResolver? apiResolver,
    this.pageSize = kGlobalThreadsPageSize,
  })  : _entryResolver = entryResolver,
        _apiResolver = apiResolver ?? ((entry) => entry.connection.api);

  final ServerEntry? Function(String serverId) _entryResolver;
  final ApiResolver _apiResolver;

  /// Threads fetched per request. Injectable so tests can force paging
  /// without standing up 50 threads.
  final int pageSize;

  final Signal<GlobalThreads> _threads = Signal(const GlobalThreadsLoading());
  ReadonlySignal<GlobalThreads> get threads => _threads;

  String? _serverId;

  /// The active filter, applied to every page including [loadMore]'s —
  /// paging a filtered listing has to stay filtered.
  List<int> _labelIds = const [];
  bool _unlabeled = false;
  String _query = '';

  /// Whether the listing is currently narrowed by a search.
  ///
  /// Lets the view tell "you have no threads" from "nothing matched",
  /// which want different empty states.
  bool get isFiltered =>
      _labelIds.isNotEmpty || _unlabeled || _query.isNotEmpty;

  /// Cancels the in-flight request, if any. Also the guard against
  /// overlapping pages: a non-null token means a fetch is already running,
  /// and [loadMore] declines rather than requesting the same page twice.
  CancelToken? _token;

  bool _disposed = false;

  /// The search box's text, kept here so a view built again (after the
  /// user comes back from a thread) shows the query its rows were
  /// filtered by. Cleared with the filter on a server switch.
  String searchText = '';

  /// How far the list was scrolled, for the same reason as [searchText].
  double scrollOffset = 0;

  /// Which server the listing is showing, or `null` when none is selected.
  String? get serverId => _serverId;

  /// Keeps the listing on [selection], and on that server's session.
  ///
  /// Returns the disposer. A screen calls this when it mounts and disposes
  /// it when it unmounts; following the same server again keeps the pages
  /// already held and re-checks the first one.
  void Function() follow({
    required ReadonlySignal<String?> selection,
    required ReadonlySignal<Map<String, ServerEntry>> servers,
  }) {
    final follower = ServerFollower(
      selection: selection,
      servers: servers,
      onServer: _onServer,
      onConnected: () => unawaited(refresh()),
      onDisconnected: _signOut,
      onRemoved: () => setServer(null),
    );
    return follower.dispose;
  }

  void _onServer(ServerEntry entry) {
    if (entry.serverId != _serverId) {
      setServer(entry.serverId);
      return;
    }

    // Back on the server already held: a remount, or the session changed
    // while nothing was following.
    if (!entry.isConnected) {
      _signOut(expired: entry.auth.session.value is ExpiredSession);
      return;
    }
    switch (_threads.value) {
      case GlobalThreadsLoaded():
        unawaited(revalidate());
      case GlobalThreadsFailed() || GlobalThreadsSignedOut():
        unawaited(refresh());
      case GlobalThreadsLoading() || GlobalThreadsUnsupported():
        break;
    }
  }

  /// Points the listing at [serverId] and loads its first page.
  ///
  /// A repeat call for the same server is a no-op, so rebuilds that re-emit
  /// the current selection do not restart paging from zero. A different
  /// server starts unfiltered: label ids belong to one server, and a filter
  /// carried over would select some other label, or none.
  void setServer(String? serverId) {
    if (serverId == _serverId) return;
    _serverId = serverId;
    _cancelInFlight();
    _labelIds = const [];
    _unlabeled = false;
    _query = '';
    searchText = '';
    scrollOffset = 0;

    if (serverId == null) {
      _threads.value = GlobalThreadsLoaded(threads: const []);
      return;
    }

    _threads.value = const GlobalThreadsLoading();
    unawaited(_fetch(cursor: null));
  }

  /// Drops the held rows when the session ends, so the next person at
  /// this screen never sees them.
  void _signOut({required bool expired}) {
    _cancelInFlight();
    scrollOffset = 0;
    _threads.value = GlobalThreadsSignedOut(expired: expired);
  }

  /// Narrows the listing to threads matching [labelIds] and [query].
  ///
  /// [labelIds] is an "any of" match; empty means no label filter, so
  /// clearing the last chip widens the listing rather than emptying it.
  /// [unlabeled] adds threads carrying no label as one more alternative.
  /// [query] matches thread names, ignoring case.
  ///
  /// A no-op when none of them has changed, so a rebuild that re-emits the
  /// current filter does not restart paging from zero.
  void setFilter({
    List<int> labelIds = const [],
    bool unlabeled = false,
    String query = '',
  }) {
    if (_sameFilter(labelIds, unlabeled, query)) return;
    _labelIds = List.unmodifiable(labelIds);
    _unlabeled = unlabeled;
    _query = query;

    if (_serverId == null) return;
    _cancelInFlight();
    _threads.value = const GlobalThreadsLoading();
    unawaited(_fetch(cursor: null));
  }

  bool _sameFilter(List<int> labelIds, bool unlabeled, String query) {
    if (query != _query || unlabeled != _unlabeled) return false;
    if (labelIds.length != _labelIds.length) return false;
    for (var i = 0; i < labelIds.length; i++) {
      if (labelIds[i] != _labelIds[i]) return false;
    }
    return true;
  }

  /// Reloads from the first page, discarding what is already held.
  Future<void> refresh() {
    if (_serverId == null) return Future<void>.value();
    _cancelInFlight();
    _threads.value = const GlobalThreadsLoading();
    return _fetch(cursor: null);
  }

  /// Appends the next page, if there is one and none is already in flight.
  ///
  /// Also the retry after a failed page: it asks for the same page again.
  Future<void> loadMore() {
    final current = _threads.value;
    if (current is! GlobalThreadsLoaded) return Future<void>.value();
    final cursor = current.nextCursor;
    if (cursor == null || _token != null) return Future<void>.value();

    _threads.value = GlobalThreadsLoaded(
      threads: current.threads,
      nextCursor: cursor,
      loadingMore: true,
    );
    return _fetch(cursor: cursor);
  }

  /// Fetches the page after [cursor], or the first page when it is `null`.
  Future<void> _fetch({required String? cursor}) async {
    final serverId = _serverId;
    if (serverId == null) return;

    final entry = _entryResolver(serverId);
    if (entry == null) {
      // The server vanished between selection and fetch (removed, or a
      // races-with-teardown rebuild). Nothing to show and nothing to log.
      _threads.value = GlobalThreadsLoaded(threads: const []);
      return;
    }

    // A request now would only come back 401.
    if (!entry.isConnected) {
      _signOut(expired: entry.auth.session.value is ExpiredSession);
      return;
    }

    final token = CancelToken();
    _token = token;

    try {
      final page = await _apiResolver(entry).getAllThreads(
        limit: pageSize,
        cursor: cursor,
        labelIds: _labelIds,
        unlabeled: _unlabeled,
        query: _query,
        cancelToken: token,
      );

      // Bail on anything that moved underneath the request: a cancel, a
      // dispose, or a server switch. Writing here would show one server's
      // threads under another's heading.
      if (token.isCancelled || _disposed || serverId != _serverId) return;
      _token = null;

      final existing = cursor == null ? const <ThreadInfo>[] : _heldThreads();
      final held = {for (final thread in existing) thread.id};
      _threads.value = GlobalThreadsLoaded(
        // A thread already held can come round again, after the first page
        // was re-checked (see [revalidate]); it keeps the row it has.
        threads: [
          ...existing,
          ...page.threads.where((thread) => !held.contains(thread.id)),
        ],
        nextCursor: page.nextCursor,
      );
    } on Object catch (error, st) {
      if (token.isCancelled || _disposed || serverId != _serverId) return;
      _token = null;

      // What this catch can see is the client's own exceptions over a
      // thread page: status codes, the server's reason, and network errors
      // naming the host. None carries a credential, and each is what makes
      // the record actionable, so 'error:' is kept.
      final held = _threads.value;
      if (cursor != null && held is GlobalThreadsLoaded) {
        // A later page: keep every row and the cursor, so a retry resumes
        // from the same page. Not "unsupported" even for a 404 -- this
        // server just served the first page.
        if (error is AuthException) entry.auth.markSessionExpired();
        _logger.warning(
          'Failed to fetch the next page of threads for $serverId',
          error: error,
          stackTrace: st,
          attributes: {'held': held.threads.length},
        );
        _threads.value = GlobalThreadsLoaded(
          threads: held.threads,
          nextCursor: cursor,
          loadMoreError: error,
        );
        return;
      }

      if (error is NotFoundException) {
        // A server that predates the cross-room endpoint, not a fault --
        // but recorded, since a wrong base URL looks the same from here.
        _logger.info(
          'No cross-room thread listing on $serverId',
          attributes: {'serverId': serverId},
        );
        _threads.value = const GlobalThreadsUnsupported();
        return;
      }

      if (error is AuthException) {
        // Let the lobby's own per-server auth funnel drive re-auth; this
        // listing just stops showing stale rows.
        entry.auth.markSessionExpired();
        _threads.value = GlobalThreadsFailed(error);
        return;
      }

      if (error is PermissionDeniedException) {
        // A standing refusal, not a fault: shown without a Retry.
        _logger.warning(
          'Not allowed to list threads on $serverId',
          error: error,
        );
        _threads.value = GlobalThreadsFailed(error);
        return;
      }

      _logger.error(
        'Failed to fetch threads for $serverId',
        error: error,
        stackTrace: st,
        attributes: {'page': 'first'},
      );
      _threads.value = GlobalThreadsFailed(error);
    }
  }

  /// Re-checks the first page, keeping every page already held.
  ///
  /// For a listing the user is returning to: threads with newer activity
  /// move to the top, and rows on the first page take their current
  /// names. Rows further down keep what they had until a [refresh] —
  /// that is the cost of keeping the user's place.
  ///
  /// When the first page shares no thread with the held rows, there may be
  /// threads between the two that neither has, so the held rows are
  /// replaced by the fresh page instead.
  ///
  /// Quiet on failure: the rows already on screen are still worth showing.
  Future<void> revalidate() async {
    final serverId = _serverId;
    if (serverId == null) return;
    if (_threads.value is! GlobalThreadsLoaded || _token != null) return;

    final entry = _entryResolver(serverId);
    if (entry == null || !entry.isConnected) return;

    final token = CancelToken();
    _token = token;

    try {
      final page = await _apiResolver(entry).getAllThreads(
        limit: pageSize,
        labelIds: _labelIds,
        unlabeled: _unlabeled,
        query: _query,
        cancelToken: token,
      );
      if (token.isCancelled || _disposed || serverId != _serverId) return;
      _token = null;

      final current = _threads.value;
      if (current is! GlobalThreadsLoaded) return;

      final fresh = {for (final thread in page.threads) thread.id};
      final overlaps = current.threads.any((t) => fresh.contains(t.id));
      if (!overlaps && page.hasMore) {
        scrollOffset = 0;
        _threads.value = GlobalThreadsLoaded(
          threads: page.threads,
          nextCursor: page.nextCursor,
        );
        return;
      }

      _threads.value = GlobalThreadsLoaded(
        threads: [
          ...page.threads,
          ...current.threads.where((thread) => !fresh.contains(thread.id)),
        ],
        nextCursor: current.nextCursor,
        loadMoreError: current.loadMoreError,
      );
    } on Object catch (error, st) {
      if (token.isCancelled || _disposed || serverId != _serverId) return;
      _token = null;

      if (error is AuthException) {
        entry.auth.markSessionExpired();
        return;
      }
      // What this catch can see is the client's own exceptions over a
      // thread page: status codes, the server's reason, and network
      // errors naming the host; no credential reaches any of them.
      _logger.warning(
        'Failed to re-check the first page of threads for $serverId',
        error: error,
        stackTrace: st,
      );
    }
  }

  /// Reads [thread] again from the server and folds it into the held list,
  /// for the properties dialog to start from (see
  /// [currentThreadProperties]).
  Future<ThreadInfo> currentProperties(ThreadInfo thread) async {
    final entry = _selectedEntry();
    if (entry == null) return thread;
    final current = await currentThreadProperties(
      _apiResolver(entry),
      thread,
      onAuthFailure: (_) => entry.auth.markSessionExpired(),
    );
    _replace(current);
    return current;
  }

  /// Saves a thread's name, description and labels (see
  /// [saveThreadProperties]), and folds what was saved into the held list.
  ///
  /// [thread] is the copy the dialog started from. Returns null on success
  /// or a sentence for the dialog.
  ///
  /// Folded rather than refetched: the backend commits its transaction
  /// after sending the response, so a listing requested straight after a
  /// write can still report the old values.
  Future<String?> saveProperties(
    ThreadInfo thread, {
    required String name,
    required String description,
    required List<int> labelIds,
  }) async {
    final entry = _selectedEntry();
    if (entry == null) return 'No server selected';

    final saved = await saveThreadProperties(
      _apiResolver(entry),
      thread,
      name: name,
      description: description,
      initialLabelIds: {for (final label in thread.labels) label.id},
      labelIds: labelIds.toSet(),
      onAuthFailure: (_) => entry.auth.markSessionExpired(),
    );
    final updated = saved.thread;
    if (updated != null) _replace(updated);
    return saved.error;
  }

  ServerEntry? _selectedEntry() {
    final serverId = _serverId;
    return serverId == null ? null : _entryResolver(serverId);
  }

  /// Renames a thread, folding the new name into the held list.
  Future<String?> rename(ThreadInfo thread, String name) {
    return _mutate(failure: 'Could not rename the thread.', (api) async {
      await api.updateThreadMetadata(
        thread.roomId,
        thread.id,
        name: name,
        // Resent rather than omitted: the metadata row is replaced
        // wholesale, so leaving this out would silently drop it.
        description: thread.description,
      );
      _replace(thread.copyWith(name: name));
    });
  }

  /// Deletes a thread and drops it from the held list.
  Future<String?> delete(ThreadInfo thread) {
    return _mutate(failure: 'Could not delete the thread.', (api) async {
      await api.deleteThread(thread.roomId, thread.id);
      final remaining = [
        for (final held in _heldThreads())
          if (held.id != thread.id) held,
      ];
      _write(remaining);
    });
  }

  /// Runs a write, returning null on success or a sentence for the dialog;
  /// [failure] names what didn't happen.
  Future<String?> _mutate(
    Future<void> Function(SoliplexApi api) body, {
    required String failure,
  }) async {
    final serverId = _serverId;
    final entry = _selectedEntry();
    if (entry == null) return 'No server selected';

    try {
      await body(_apiResolver(entry));
      return null;
    } on Object catch (error, st) {
      if (_disposed) return null;
      if (error is AuthException) {
        // The same re-auth path a failed read takes, rather than a
        // message the user can do nothing with.
        entry.auth.markSessionExpired();
      }
      _logger.error(
        'Thread operation failed for $serverId',
        error: error,
        stackTrace: st,
      );
      return switch (error) {
        NotFoundException() => 'This thread no longer exists.',
        AuthException() => 'Your session has ended. Sign in again, then retry.',
        // Retrying can't help, so it isn't offered.
        PermissionDeniedException() =>
          "You don't have permission to change this thread.",
        NetworkException() =>
          "$failure Can't reach the server; check your connection.",
        _ => '$failure Please try again.',
      };
    }
  }

  /// Swaps [thread] into the held list, leaving its position alone.
  ///
  /// Position is preserved rather than re-sorted: the list is ordered by
  /// activity, most recent first, and the cursor pages through that
  /// order. Moving a thread would break it, and having a thread jump
  /// elsewhere the instant it is renamed would lose the row the user was
  /// looking at.
  void _replace(ThreadInfo thread) {
    _write([
      for (final held in _heldThreads())
        if (held.id == thread.id) thread else held,
    ]);
  }

  void _write(List<ThreadInfo> threads) {
    if (_disposed) return;
    final current = _threads.value;
    if (current is! GlobalThreadsLoaded) return;
    _threads.value = GlobalThreadsLoaded(
      threads: threads,
      nextCursor: current.nextCursor,
      loadingMore: current.loadingMore,
      loadMoreError: current.loadMoreError,
    );
  }

  List<ThreadInfo> _heldThreads() {
    final current = _threads.value;
    return current is GlobalThreadsLoaded ? current.threads : const [];
  }

  void _cancelInFlight() {
    _token?.cancel('superseded');
    _token = null;
  }

  void dispose() {
    _disposed = true;
    _cancelInFlight();
  }
}
