import 'dart:async';

import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;
import 'package:soliplex_client/soliplex_client.dart'
    show AuthException, NotFoundException;
import 'package:soliplex_logging/soliplex_logging.dart';

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

/// The first page is in flight; nothing is on screen yet.
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
    required this.hasMore,
    required this.loadingMore,
  }) : threads = List.unmodifiable(threads);

  final List<ThreadInfo> threads;
  final bool hasMore;
  final bool loadingMore;
}

/// The listing could not be loaded.
final class GlobalThreadsFailed extends GlobalThreads {
  const GlobalThreadsFailed(this.error);
  final Object error;
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
/// no coherent global ordering. [setServer] follows the lobby's selection.
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

  /// Cancels the in-flight request, if any. Also the guard against
  /// overlapping pages: a non-null token means a fetch is already running,
  /// and [loadMore] declines rather than requesting the same offset twice.
  CancelToken? _token;

  bool _disposed = false;

  /// Which server the listing is showing, or `null` when none is selected.
  String? get serverId => _serverId;

  /// Points the listing at [serverId] and loads its first page.
  ///
  /// A repeat call for the same server is a no-op, so rebuilds that re-emit
  /// the current selection do not restart paging from zero.
  void setServer(String? serverId) {
    if (serverId == _serverId) return;
    _serverId = serverId;
    _cancelInFlight();

    if (serverId == null) {
      _threads.value = GlobalThreadsLoaded(
        threads: const [],
        hasMore: false,
        loadingMore: false,
      );
      return;
    }

    _threads.value = const GlobalThreadsLoading();
    unawaited(_fetch(offset: 0));
  }

  /// Reloads from the first page, discarding what is already held.
  Future<void> refresh() {
    if (_serverId == null) return Future<void>.value();
    _cancelInFlight();
    _threads.value = const GlobalThreadsLoading();
    return _fetch(offset: 0);
  }

  /// Appends the next page, if there is one and none is already in flight.
  Future<void> loadMore() {
    final current = _threads.value;
    if (current is! GlobalThreadsLoaded) return Future<void>.value();
    if (!current.hasMore || _token != null) return Future<void>.value();

    _threads.value = GlobalThreadsLoaded(
      threads: current.threads,
      hasMore: current.hasMore,
      loadingMore: true,
    );
    return _fetch(offset: current.threads.length);
  }

  Future<void> _fetch({required int offset}) async {
    final serverId = _serverId;
    if (serverId == null) return;

    final entry = _entryResolver(serverId);
    if (entry == null) {
      // The server vanished between selection and fetch (removed, or a
      // races-with-teardown rebuild). Nothing to show and nothing to log.
      _threads.value = GlobalThreadsLoaded(
        threads: const [],
        hasMore: false,
        loadingMore: false,
      );
      return;
    }

    final token = CancelToken();
    _token = token;

    try {
      final page = await _apiResolver(entry).getAllThreads(
        limit: pageSize,
        offset: offset,
        cancelToken: token,
      );

      // Bail on anything that moved underneath the request: a cancel, a
      // dispose, or a server switch. Writing here would show one server's
      // threads under another's heading.
      if (token.isCancelled || _disposed || serverId != _serverId) return;
      _token = null;

      final existing = offset == 0 ? const <ThreadInfo>[] : _heldThreads();
      _threads.value = GlobalThreadsLoaded(
        threads: [...existing, ...page.threads],
        hasMore: page.hasMore,
        loadingMore: false,
      );
    } on Object catch (error, st) {
      if (token.isCancelled || _disposed || serverId != _serverId) return;
      _token = null;

      if (error is NotFoundException) {
        // A server that predates the cross-room endpoint, not a fault.
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

      _logger.error(
        'Failed to fetch threads for $serverId',
        error: error,
        stackTrace: st,
      );
      _threads.value = GlobalThreadsFailed(error);
    }
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
