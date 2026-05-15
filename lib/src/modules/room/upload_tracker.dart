import 'dart:async' show unawaited;
import 'dart:developer' as dev;

import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_client/soliplex_client.dart';

/// Sealed status for a single upload scope (a room or a thread).
///
/// A refresh failure from a `Loaded` state is logged but not surfaced
/// — the prior list stays visible. `Failed` only fires from a
/// non-`Loaded` baseline.
sealed class UploadsStatus {
  const UploadsStatus();
}

class UploadsLoading extends UploadsStatus {
  const UploadsLoading();
}

class UploadsLoaded extends UploadsStatus {
  const UploadsLoaded(this.uploads);
  final List<DisplayUpload> uploads;
}

class UploadsFailed extends UploadsStatus {
  const UploadsFailed(this.error);
  final SoliplexException error;
}

sealed class DisplayUpload {
  const DisplayUpload({required this.filename});
  final String filename;
}

class PersistedUpload extends DisplayUpload {
  const PersistedUpload({required super.filename, required this.url});
  final Uri url;
}

class PendingUpload extends DisplayUpload {
  const PendingUpload({
    required this.id,
    required super.filename,
    required this.sentBytes,
    required this.totalBytes,
  });
  final String id;

  /// Bytes successfully sent for the in-flight POST. After the server
  /// confirms the upload (but before the persisted list refresh observes
  /// it), this equals [totalBytes] — the row shows 100% briefly.
  final int sentBytes;

  /// Declared content length of the upload, used to compute progress.
  /// Equal to the file size for single-file uploads.
  final int totalBytes;

  /// Progress in `[0, 1]`, or `null` for indeterminate (empty file or
  /// unknown length).
  double? get progress {
    if (totalBytes <= 0) return null;
    return (sentBytes / totalBytes).clamp(0.0, 1.0);
  }
}

class FailedUpload extends DisplayUpload {
  const FailedUpload({
    required this.id,
    required super.filename,
    required this.message,
  });
  final String id;
  final String message;
}

/// Formats an error for user display without leaking raw exception
/// internals (stack frames, request URLs, auth headers). Extracts the
/// message from known [SoliplexException] subtypes; falls back to a
/// fixed, translatable string for anything else.
String uploadErrorMessage(Object error) {
  if (error is SoliplexException) return error.message;
  return 'Something went wrong. Please try again.';
}

/// Internal record for a local upload row. Sealed and immutable:
/// transitions happen by replacing the record at the same index, not
/// by mutation.
sealed class _PendingRecord {
  const _PendingRecord({required this.id, required this.filename});
  final String id;
  final String filename;
}

class _Pending extends _PendingRecord {
  const _Pending({
    required super.id,
    required super.filename,
    required this.cancelToken,
    required this.sentBytes,
    required this.totalBytes,
  });

  /// Cancellation handle for the in-flight POST. [UploadTracker.dispose]
  /// cancels every active token so background uploads on detached
  /// trackers don't keep running.
  final CancelToken cancelToken;

  /// Bytes the source stream has yielded so far. Updated as the wrapped
  /// `openStream` factory observes chunks flowing into the multipart
  /// encoder.
  final int sentBytes;

  /// Declared content length of the upload (multipart preamble and
  /// footer are NOT included — this is the file body length).
  final int totalBytes;
}

/// Server-confirmed via POST but not yet observed in the persisted
/// list. A concurrent refresh may cancel the one that would have
/// cleaned this record up; the next refresh whose response contains
/// the filename finally drops it.
class _Posted extends _PendingRecord {
  const _Posted({
    required super.id,
    required super.filename,
    required this.totalBytes,
  });

  /// Carried forward from `_Pending` so the row still reports 100%
  /// while waiting for the refresh that drops it.
  final int totalBytes;
}

class _Failed extends _PendingRecord {
  const _Failed({
    required super.id,
    required super.filename,
    required this.message,
  });
  final String message;
}

class _ScopeState {
  _ScopeState() : signal = Signal<UploadsStatus>(const UploadsLoading());

  List<FileUpload>? persisted;
  final List<_PendingRecord> pending = [];
  CancelToken? fetchToken;
  final Signal<UploadsStatus> signal;

  void dispose() {
    fetchToken?.cancel('disposed');
    signal.dispose();
  }
}

/// Tracks file uploads across rooms and threads, merging a
/// server-fetched list with an in-flight optimistic view.
///
/// Owned by the registry so uploads started on one screen survive
/// when the user navigates away before the POST resolves.
class UploadTracker {
  UploadTracker({required SoliplexApi api}) : _api = api;

  final SoliplexApi _api;
  final Map<String, _ScopeState> _scopes = {};
  bool _isDisposed = false;
  int _nextId = 0;

  /// True after [dispose] has been called.
  bool get isDisposed => _isDisposed;

  static String _roomKey(String roomId) => 'room:$roomId';
  static String _threadKey(String roomId, String threadId) =>
      'thread:$roomId:$threadId';

  _ScopeState _scope(String key) => _scopes.putIfAbsent(key, _ScopeState.new);

  // --------------------------------------------------------
  // Public signals
  // --------------------------------------------------------

  ReadonlySignal<UploadsStatus> roomUploads(String roomId) {
    _requireNotDisposed();
    return _scope(_roomKey(roomId)).signal;
  }

  ReadonlySignal<UploadsStatus> threadUploads(
    String roomId,
    String threadId,
  ) {
    _requireNotDisposed();
    return _scope(_threadKey(roomId, threadId)).signal;
  }

  void _requireNotDisposed() {
    if (_isDisposed) {
      throw StateError('UploadTracker has been disposed');
    }
  }

  // --------------------------------------------------------
  // Refresh triggers
  // --------------------------------------------------------

  Future<void> refreshRoom(String roomId) {
    return _refresh(
      key: _roomKey(roomId),
      fetch: (token) => _api.getRoomUploads(roomId, cancelToken: token),
    );
  }

  Future<void> refreshThread(String roomId, String threadId) {
    return _refresh(
      key: _threadKey(roomId, threadId),
      fetch: (token) =>
          _api.getThreadUploads(roomId, threadId, cancelToken: token),
    );
  }

  Future<void> _refresh({
    required String key,
    required Future<List<FileUpload>> Function(CancelToken) fetch,
  }) {
    if (_isDisposed) return Future<void>.value();
    return _fetch(scope: _scope(key), fetch: fetch);
  }

  Future<void> _fetch({
    required _ScopeState scope,
    required Future<List<FileUpload>> Function(CancelToken) fetch,
  }) async {
    if (_isDisposed) return;
    scope.fetchToken?.cancel('re-fetch');
    final token = CancelToken();
    scope.fetchToken = token;

    if (scope.signal.value is! UploadsLoaded) {
      scope.signal.value = const UploadsLoading();
    }

    try {
      final list = await fetch(token);
      if (token.isCancelled || _isDisposed) return;
      scope.fetchToken = null;
      scope.persisted = list;

      // Clean up posted records once their filename lands in the
      // server list. Handled here rather than in `_runUpload` so a
      // refresh cancelled by a concurrent one doesn't strand the
      // posted record.
      final names = list.map((f) => f.filename).toSet();
      scope.pending.removeWhere(
        (r) => r is _Posted && names.contains(r.filename),
      );

      _emit(scope);
    } on CancelledException {
      // Fetch was superseded or the tracker is tearing down.
      return;
    } on SoliplexException catch (error) {
      if (token.isCancelled || _isDisposed) return;
      scope.fetchToken = null;
      if (scope.signal.value is UploadsLoaded) {
        dev.log(
          'Upload list refresh failed, keeping stale list',
          error: error,
          name: 'UploadTracker',
        );
      } else {
        scope.signal.value = UploadsFailed(error);
      }
    } on Object catch (error, stackTrace) {
      // Belt-and-braces: anything that isn't a SoliplexException
      // (including `Error` subtypes like TypeError from a bad cast)
      // would otherwise leave the scope in UploadsLoading with a live
      // fetchToken, wedging future refreshes. Wrap and surface.
      if (token.isCancelled || _isDisposed) return;
      scope.fetchToken = null;
      dev.log(
        'Unexpected error in upload list refresh',
        error: error,
        stackTrace: stackTrace,
        name: 'UploadTracker',
        level: 1000,
      );
      if (scope.signal.value is UploadsLoaded) {
        return;
      }
      scope.signal.value = UploadsFailed(UnexpectedException(
        message: 'Unexpected error while loading uploads',
        originalError: error,
        stackTrace: stackTrace,
      ));
    }
  }

  // --------------------------------------------------------
  // Upload actions
  // --------------------------------------------------------

  void uploadToRoom({
    required String roomId,
    required String filename,
    required Stream<List<int>> Function() openStream,
    required int contentLength,
    String mimeType = 'application/octet-stream',
  }) {
    final key = _roomKey(roomId);
    _startUpload(
      key: key,
      filename: filename,
      openStream: openStream,
      contentLength: contentLength,
      runPost: (wrappedOpenStream, token) => _api.uploadFileToRoom(
        roomId,
        filename: filename,
        openStream: wrappedOpenStream,
        contentLength: contentLength,
        mimeType: mimeType,
        cancelToken: token,
      ),
      refresh: () => _refresh(
        key: key,
        fetch: (token) => _api.getRoomUploads(roomId, cancelToken: token),
      ),
    );
  }

  void uploadToThread({
    required String roomId,
    required String threadId,
    required String filename,
    required Stream<List<int>> Function() openStream,
    required int contentLength,
    String mimeType = 'application/octet-stream',
  }) {
    final key = _threadKey(roomId, threadId);
    _startUpload(
      key: key,
      filename: filename,
      openStream: openStream,
      contentLength: contentLength,
      runPost: (wrappedOpenStream, token) => _api.uploadFileToThread(
        roomId,
        threadId,
        filename: filename,
        openStream: wrappedOpenStream,
        contentLength: contentLength,
        mimeType: mimeType,
        cancelToken: token,
      ),
      refresh: () => _refresh(
        key: key,
        fetch: (token) =>
            _api.getThreadUploads(roomId, threadId, cancelToken: token),
      ),
    );
  }

  /// Number of times a streamed POST is re-attempted after an
  /// `AuthException`. One retry suffices for the transient
  /// token-expired-mid-upload case: between attempts the request
  /// re-enters `RefreshingHttpClient`, which runs proactive refresh on
  /// every dispatch and replaces the stale token before attempt 2.
  /// If the second attempt still 401s, refresh itself is broken (e.g.
  /// signed out elsewhere) — more attempts wouldn't help.
  static const int _maxAuthRetries = 1;

  /// Progress emissions are coalesced to one signal update per
  /// 50 ms (≈20 Hz) per upload. Final emission (`sent == total`)
  /// always fires regardless of throttle.
  static const Duration _progressEmitInterval = Duration(milliseconds: 50);

  void _startUpload({
    required String key,
    required String filename,
    required Stream<List<int>> Function() openStream,
    required int contentLength,
    required Future<void> Function(
      Stream<List<int>> Function(),
      CancelToken,
    ) runPost,
    required Future<void> Function() refresh,
  }) {
    if (_isDisposed) return;
    final scope = _scope(key);
    final id = 'upload-${_nextId++}';
    final token = CancelToken();
    scope.pending.add(
      _Pending(
        id: id,
        filename: filename,
        cancelToken: token,
        sentBytes: 0,
        totalBytes: contentLength,
      ),
    );
    _emit(scope);

    // Wrap [openStream] so we can observe chunks as they flow into the
    // multipart encoder. Local state is captured per-call; on retry,
    // the wrapper is re-invoked and the counters reset.
    Stream<List<int>> wrappedOpenStream() async* {
      var sent = 0;
      DateTime? lastEmit;
      await for (final chunk in openStream()) {
        yield chunk;
        sent += chunk.length;
        final isFinal = sent >= contentLength;
        final now = DateTime.now();
        final dueByThrottle = lastEmit == null ||
            now.difference(lastEmit) >= _progressEmitInterval;
        if (isFinal || dueByThrottle) {
          lastEmit = now;
          _updateProgress(scope, id, sent);
        }
      }
    }

    unawaited(
      _runUpload(
        scope: scope,
        id: id,
        runPost: (t) => runPost(wrappedOpenStream, t),
        refresh: refresh,
        token: token,
      ),
    );
  }

  /// Replaces the `_Pending` record at [id] with an updated [sentBytes]
  /// count, then emits the signal. Silent no-op if the record is gone
  /// (already Posted/Failed) or the tracker is disposed.
  void _updateProgress(_ScopeState scope, String id, int sentBytes) {
    if (_isDisposed) return;
    final idx = scope.pending.indexWhere((r) => r.id == id);
    if (idx < 0) return;
    final record = scope.pending[idx];
    if (record is! _Pending) return;
    scope.pending[idx] = _Pending(
      id: id,
      filename: record.filename,
      cancelToken: record.cancelToken,
      sentBytes: sentBytes,
      totalBytes: record.totalBytes,
    );
    _emit(scope);
  }

  Future<void> _runUpload({
    required _ScopeState scope,
    required String id,
    required Future<void> Function(CancelToken) runPost,
    required Future<void> Function() refresh,
    required CancelToken token,
  }) async {
    for (var retries = 0; retries <= _maxAuthRetries; retries++) {
      try {
        await runPost(token);
        if (_isDisposed) return;

        // Replace _Pending with _Posted at the same index. The actual
        // removal happens in `_fetch` once the filename appears in the
        // server list.
        final idx = scope.pending.indexWhere((r) => r.id == id);
        if (idx < 0) return; // Dismissed during POST.
        final record = scope.pending[idx];
        if (record is _Pending) {
          scope.pending[idx] = _Posted(
            id: id,
            filename: record.filename,
            totalBytes: record.totalBytes,
          );
        }

        unawaited(refresh());
        return;
      } on CancelledException {
        // Tracker is being disposed or upload was cancelled externally.
        // No Failed row needed; the dispose path tears the scope down.
        return;
      } on AuthException catch (error) {
        if (_isDisposed) return;
        if (retries < _maxAuthRetries) {
          // The next attempt re-invokes openStream() (via runPost) and
          // re-enters the auth-aware HTTP stack, which gets a fresh
          // proactive refresh.
          dev.log(
            'Upload hit 401; retrying with a fresh stream',
            error: error,
            name: 'UploadTracker',
          );
          continue;
        }
        _markFailed(scope, id, error);
        return;
      } on Object catch (error, stackTrace) {
        if (_isDisposed) return;
        if (error is! SoliplexException) {
          // Non-Soliplex throw indicates a bug (e.g., TypeError from a
          // mapper, StateError from a plugin). Log loudly; the user
          // still sees a Failed row via uploadErrorMessage's fallback.
          dev.log(
            'Unexpected error during upload POST',
            error: error,
            stackTrace: stackTrace,
            name: 'UploadTracker',
            level: 1000,
          );
        }
        _markFailed(scope, id, error);
        return;
      }
    }
  }

  void _markFailed(_ScopeState scope, String id, Object error) {
    final idx = scope.pending.indexWhere((r) => r.id == id);
    if (idx < 0) {
      // The dismiss path shouldn't be reachable (UI dismisses only
      // Failed rows); log loudly if it ever fires so the swallowed
      // exception is investigated.
      dev.log(
        'Upload completed after its pending record was removed',
        error: error,
        name: 'UploadTracker',
        level: 1000,
      );
      return;
    }
    scope.pending[idx] = _Failed(
      id: id,
      filename: scope.pending[idx].filename,
      message: uploadErrorMessage(error),
    );
    _emit(scope);
  }

  // --------------------------------------------------------
  // Client-side failures
  // --------------------------------------------------------

  /// Records an upload failure that happened before any POST was
  /// attempted (e.g., local file read error). Surfaces as a
  /// `FailedUpload` row so the user sees the same inline feedback
  /// as a server-side failure.
  void recordClientError({
    required String roomId,
    String? threadId,
    required String filename,
    required String message,
  }) {
    if (_isDisposed) return;
    final key =
        threadId == null ? _roomKey(roomId) : _threadKey(roomId, threadId);
    final scope = _scope(key);
    final id = 'upload-${_nextId++}';
    scope.pending.add(_Failed(id: id, filename: filename, message: message));
    _emit(scope);
  }

  // --------------------------------------------------------
  // Dismissal
  // --------------------------------------------------------

  /// Removes a Failed entry by its id.
  ///
  /// Restricted to Failed records because removing a Pending or
  /// Posted mid-flight would misrepresent the upload's state to
  /// observers that diff the signal.
  void dismissFailed(String entryId) {
    if (_isDisposed) return;
    for (final scope in _scopes.values) {
      final idx = scope.pending.indexWhere((r) => r.id == entryId);
      if (idx < 0) continue;
      final record = scope.pending[idx];
      if (record is! _Failed) {
        assert(
          false,
          'dismissFailed called on ${record.runtimeType}; '
          'only Failed records may be dismissed',
        );
        return;
      }
      scope.pending.removeAt(idx);
      _emit(scope);
      return;
    }
  }

  // --------------------------------------------------------
  // Signal emission
  // --------------------------------------------------------

  void _emit(_ScopeState scope) {
    if (_isDisposed) return;
    final persisted = scope.persisted;
    final merged = <DisplayUpload>[
      if (persisted != null)
        for (final f in persisted)
          PersistedUpload(filename: f.filename, url: f.url),
      for (final p in scope.pending)
        switch (p) {
          _Pending(
            :final id,
            :final filename,
            :final sentBytes,
            :final totalBytes,
          ) =>
            PendingUpload(
              id: id,
              filename: filename,
              sentBytes: sentBytes,
              totalBytes: totalBytes,
            ),
          _Posted(:final id, :final filename, :final totalBytes) =>
            PendingUpload(
              id: id,
              filename: filename,
              sentBytes: totalBytes,
              totalBytes: totalBytes,
            ),
          _Failed(:final id, :final filename, :final message) =>
            FailedUpload(id: id, filename: filename, message: message),
        },
    ];

    // No server list yet and nothing local: keep the current Loading
    // or Failed status; don't prematurely emit Loaded([]).
    if (persisted == null && merged.isEmpty) return;

    scope.signal.value = UploadsLoaded(List.unmodifiable(merged));
  }

  // --------------------------------------------------------
  // Lifecycle
  // --------------------------------------------------------

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    for (final scope in _scopes.values) {
      // Cancel any in-flight uploads. The POST futures see the
      // injected sink error and abort cleanly; _runUpload catches the
      // CancelledException and exits without writing a Failed row.
      for (final record in scope.pending) {
        if (record is _Pending) {
          record.cancelToken.cancel('disposed');
        }
      }
      scope.dispose();
    }
    _scopes.clear();
  }
}
