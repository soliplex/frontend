import 'dart:async' show unawaited;
import 'dart:collection' show Queue;
import 'dart:io' show FileSystemException, SocketException;

import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../auth/auth_session.dart';
import '../auth/auth_tokens.dart';

final Logger _logger = LogManager.instance.getLogger('soliplex.upload_tracker');

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
  const PersistedUpload({
    required super.filename,
    required this.url,
    this.isDeleting = false,
  });
  final Uri url;

  /// Whether a delete of this file is waiting on the server.
  final bool isDeleting;
}

class PendingUpload extends DisplayUpload {
  const PendingUpload({
    required this.id,
    required super.filename,
    required this.sentBytes,
    required this.totalBytes,
  });
  final String id;

  /// Bytes the current attempt has counted as sent: file bytes on native,
  /// request-body bytes on the web, so it can pass [totalBytes] there. Holds
  /// at [totalBytes] or more from the attempt's last byte until the row
  /// leaves pending, dropped by the next upload list or replaced by a
  /// failure. A retry after a 401 counts again from zero once its first
  /// chunk is counted.
  final int sentBytes;

  /// Declared content length of the upload, used to compute progress.
  /// Equal to the file size for single-file uploads.
  final int totalBytes;

  /// Progress in `[0, 1)`, or `null` for indeterminate: an empty file, an
  /// unknown length, or every byte sent, which also covers a web count past
  /// [totalBytes]. Once every byte is sent, what remains (the server's answer
  /// and the next list) has no measure, and a full ring would read as done.
  double? get progress {
    if (totalBytes <= 0 || allBytesSent) return null;
    return sentBytes / totalBytes;
  }

  /// Whether the count has reached [totalBytes]: on the web, request-body
  /// bytes the browser has sent, which reach the file's size a little before
  /// the body ends; on native, file bytes handed to the request's encoder,
  /// which can run ahead of the network. False for an empty file or an
  /// unknown length, which have no last byte to count.
  ///
  /// An upload whose whole body reached the server is kept even when its
  /// request is then aborted (observed for room uploads; thread uploads take
  /// the same path), so a cancel from here on may not stop the file landing.
  bool get allBytesSent => totalBytes > 0 && sentBytes >= totalBytes;
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
/// internals (stack frames, request URLs, auth headers). Maps a few
/// upload-specific failure modes to friendlier messages before falling
/// back to the [SoliplexException.message], then to a generic string.
String uploadErrorMessage(Object error) {
  if (error is ApiException) {
    // 413 Request Entity Too Large — backend or edge proxy rejected
    // the upload size. Surfaces the same friendly message regardless
    // of whether the body said anything useful.
    if (error.statusCode == 413) return 'File is too large to upload.';
    if (error.statusCode == 415) return "This file type isn't supported.";
    // The server accepts uploads for this scope only when the installation
    // configures a path for it. Nothing the user can act on.
    if (error.statusCode == 405) {
      return "File uploads aren't configured on this server.";
    }
    if (error.statusCode >= 500) {
      return 'Server is temporarily unavailable. '
          'Try uploading again in a moment.';
    }
  }

  // The lazy openStream() failed to read the file (typical cause: the
  // user moved or deleted the file between picking and upload).
  // Surfaces as the API call's `cause` inside NetworkException — and
  // also directly when the picker reads bytes server-side. Match both
  // by inspecting the error and its originalError.
  if (_isFileSystemRead(error)) {
    return 'Could not read file from disk.';
  }

  if (error is NetworkException) {
    if (error.isTimeout) {
      return 'Upload timed out. Try a smaller file or check your connection.';
    }
    if (error.originalError is SocketException) {
      return 'Network connection lost. Try uploading again.';
    }
  }

  if (error is AuthException && error.statusCode == 401) {
    return 'Session expired. Please sign in again.';
  }

  if (error is PermissionDeniedException) {
    return "You don't have permission to upload here.";
  }

  if (error is SoliplexException) return error.message;
  return 'Something went wrong. Please try again.';
}

/// Says why a room upload could not be deleted, in words for the user.
String deleteErrorMessage(Object error) {
  const failed = "Couldn't delete:";
  return switch (error) {
    PermissionDeniedException() =>
      "$failed you don't have permission to delete files here.",
    ApiException(statusCode: 405) =>
      "$failed file uploads aren't configured on this server.",
    NetworkException() => "$failed the server can't be reached. Try again.",
    AuthException() => '$failed your session expired. Sign in again.',
    SoliplexException(:final message) => '$failed $message',
    _ => "Couldn't delete this file. Try again.",
  };
}

bool _isFileSystemRead(Object error) {
  if (error is FileSystemException) return true;
  if (error is SoliplexException && error.originalError != null) {
    return error.originalError is FileSystemException;
  }
  return false;
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
/// list. The next list to load successfully drops it, whether or not
/// it holds the file; see `_fetch` for why that list can be trusted.
class _Posted extends _PendingRecord {
  const _Posted({
    required super.id,
    required super.filename,
    required this.totalBytes,
  });

  /// Carried forward from `_Pending` so the row still counts every byte as
  /// sent until the refresh that drops it.
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

  /// Deletes waiting on the server, keyed by filename.
  final Map<String, CancelToken> deleting = {};

  void dispose() {
    fetchToken?.cancel('disposed');
    for (final token in deleting.values) {
      token.cancel('disposed');
    }
    signal.dispose();
  }
}

/// One pending upload job waiting for the global queue's drainer.
///
/// The job's `cancelToken` is the same instance stored on the matching
/// `_Pending` record in `scope.pending`, so `dispose()` cancels both
/// in-flight jobs (whose POST observes the token error) and
/// queued-but-not-started jobs (the drainer sees the cancelled token
/// and skips them).
class _QueuedJob {
  _QueuedJob({
    required this.scope,
    required this.id,
    required this.runPost,
    required this.refresh,
    required this.token,
  });
  final _ScopeState scope;
  final String id;
  final Future<void> Function(CancelToken) runPost;
  final Future<void> Function() refresh;
  final CancelToken token;
}

/// Tracks file uploads across rooms and threads, merging a
/// server-fetched list with an in-flight optimistic view.
///
/// Owned by the registry so uploads started on one screen survive
/// when the user navigates away before the POST resolves.
///
/// All uploads (room and thread) flow through a single global FIFO
/// queue: one job is in flight at a time. The user sees a Pending row
/// for every enqueued upload immediately, regardless of where it sits
/// in the queue.
///
/// Deleting a room upload does not use that queue: a delete is sent at
/// once, at most one per file at a time.
class UploadTracker {
  UploadTracker({required SoliplexApi api, required AuthSession auth})
      : _api = api,
        _auth = auth {
    _authUnsub = _auth.session.subscribe(_onAuthChanged);
  }

  final SoliplexApi _api;
  final AuthSession _auth;
  void Function()? _authUnsub;
  final Map<String, _ScopeState> _scopes = {};
  final Queue<_QueuedJob> _queue = Queue<_QueuedJob>();
  bool _draining = false;
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

      // Every posted record goes, listed or not. A record becomes posted
      // in the same synchronous step that starts a refresh, and starting
      // one cancels every refresh before it, so a list that lands here
      // was asked for after each POST it could describe had finished:
      // a posted file it leaves out is gone, deleted here or elsewhere.
      // Waiting for its name would strand that row, spinning.
      scope.pending.removeWhere((r) => r is _Posted);

      _emit(scope);
    } on CancelledException {
      // Fetch was superseded or the tracker is tearing down.
      return;
    } on AuthException catch (error) {
      // Must precede the SoliplexException arm: keeping a stale Loaded
      // list while the access token is dead would let the user click
      // through a stale view and silently 401 on the next mutation.
      // The route guard handles navigation; this tracker's signal is
      // no longer the UX channel for an auth failure.
      if (token.isCancelled || _isDisposed) return;
      scope.fetchToken = null;
      _logger.warning(
        'Upload list refresh hit AuthException; funneling to markSessionExpired',
        error: error,
      );
      _auth.markSessionExpired();
    } on NotFoundException {
      // Must precede the SoliplexException arm. A scope the installation
      // configures no upload path for has no list to give, and the server says
      // so with a 404 — an empty shelf rather than a failure to reach one.
      // Rendering that as a failure put a permanent error row on every visit to
      // a room not set up for uploads to this scope.
      //
      // Only where nothing has loaded yet, which is that room on every refresh.
      // The same bare 404 also answers an unknown room and one this user may no
      // longer read, because the membership check runs ahead of the path check,
      // and a list already on screen must not be retracted on either. Those
      // keep the list, on the same terms as any other refresh failure.
      //
      // The empty shelf is deliberately unrecorded: for such a room it is the
      // answer every time, so a record would be one line per room entry
      // describing a configuration working as intended. A 404 arriving after a
      // load cannot be that configuration, so that one is recorded. Neither
      // touches `pending`, so a pick failure already filed here survives.
      if (token.isCancelled || _isDisposed) return;
      scope.fetchToken = null;
      if (scope.persisted == null) {
        scope.persisted = const [];
        _emit(scope);
        return;
      }
      // The exception carries the server's own text and the path it was built
      // from, and neither adds to what this line already says.
      _logger.warning('Upload list refresh 404d after a load; keeping it');
    } on SoliplexException catch (error) {
      if (token.isCancelled || _isDisposed) return;
      scope.fetchToken = null;
      if (scope.signal.value is UploadsLoaded) {
        _logger.warning(
          'Upload list refresh failed, keeping stale list',
          error: error,
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
      _logger.error(
        'Unexpected error in upload list refresh',
        error: error,
        stackTrace: stackTrace,
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
    Object? webFileBlob,
  }) {
    final key = _roomKey(roomId);
    _startUpload(
      key: key,
      filename: filename,
      openStream: openStream,
      contentLength: contentLength,
      runPost: (wrappedOpenStream, onProgress, token) => _api.uploadFileToRoom(
        roomId,
        filename: filename,
        openStream: wrappedOpenStream,
        contentLength: contentLength,
        mimeType: mimeType,
        webFileBlob: webFileBlob,
        onProgress: onProgress,
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
    Object? webFileBlob,
  }) {
    final key = _threadKey(roomId, threadId);
    _startUpload(
      key: key,
      filename: filename,
      openStream: openStream,
      contentLength: contentLength,
      runPost: (wrappedOpenStream, onProgress, token) =>
          _api.uploadFileToThread(
        roomId,
        threadId,
        filename: filename,
        openStream: wrappedOpenStream,
        contentLength: contentLength,
        mimeType: mimeType,
        webFileBlob: webFileBlob,
        onProgress: onProgress,
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
      void Function(int sent, int total) onProgress,
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

    // Shared throttled progress emitter. The wrapper (native streaming
    // path) and the web FormData path both feed this. Throttle state
    // is per upload — captured by closure. On retry, the wrapper is
    // re-invoked but the throttle continues from where it was; the
    // worst case is one missed emission per retry, negligible.
    DateTime? lastEmit;
    void emitProgress(int sent, int total) {
      if (_isDisposed) return;
      final isFinal = sent >= total;
      final now = DateTime.now();
      final dueByThrottle = lastEmit == null ||
          now.difference(lastEmit!) >= _progressEmitInterval;
      if (isFinal || dueByThrottle) {
        lastEmit = now;
        _updateProgress(scope, id, sent);
      }
    }

    // Wrap [openStream] so we can observe chunks as they flow into the
    // multipart encoder. Only invoked on the native streaming path; on
    // the web FormData path, openStream is never called — progress
    // comes from xhr.upload.onprogress via the [emitProgress] callback
    // wired into the WebMultipartFileBody body type.
    Stream<List<int>> wrappedOpenStream() async* {
      var sent = 0;
      await for (final chunk in openStream()) {
        yield chunk;
        sent += chunk.length;
        emitProgress(sent, contentLength);
      }
    }

    _enqueue(
      _QueuedJob(
        scope: scope,
        id: id,
        runPost: (t) => runPost(wrappedOpenStream, emitProgress, t),
        refresh: refresh,
        token: token,
      ),
    );
  }

  void _enqueue(_QueuedJob job) {
    if (_isDisposed) return;
    _queue.addLast(job);
    if (!_draining) {
      _draining = true;
      unawaited(_drain());
    }
  }

  Future<void> _drain() async {
    try {
      while (_queue.isNotEmpty && !_isDisposed) {
        final job = _queue.removeFirst();
        if (job.token.isCancelled) continue;
        await _runUpload(
          scope: job.scope,
          id: job.id,
          runPost: job.runPost,
          refresh: job.refresh,
          token: job.token,
        );
      }
    } finally {
      _draining = false;
    }
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
        // removal happens in `_fetch`, when the refresh started below, or
        // a later one, lands.
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
          _logger.warning(
            'Upload hit 401; retrying with a fresh stream',
            error: error,
          );
          continue;
        }
        // Retries exhausted: commit the failed row first so the
        // tracker state is consistent before any auth-change listener
        // observes the flip and reacts.
        _markFailed(scope, id, error);
        _auth.markSessionExpired();
        return;
      } on Object catch (error, stackTrace) {
        if (_isDisposed) return;
        if (error is! SoliplexException) {
          // Non-Soliplex throw indicates a bug (e.g., TypeError from a
          // mapper, StateError from a plugin). Log loudly; the user
          // still sees a Failed row via uploadErrorMessage's fallback.
          _logger.error(
            'Unexpected error during upload POST',
            error: error,
            stackTrace: stackTrace,
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
      _logger.error(
        'Upload completed after its pending record was removed',
        error: error,
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
  // User-initiated cancel / dismissal
  // --------------------------------------------------------

  /// User-initiated cancel of an in-flight or queued Pending upload.
  ///
  /// Flips the matching `_Pending` row to a `_Failed` row carrying
  /// `'Upload cancelled.'`, then cancels its token. Order matters: by
  /// the time the in-flight POST aborts with `CancelledException`,
  /// `_runUpload`'s existing silent-exit-on-cancel path observes the
  /// record is no longer `_Pending` and won't overwrite the Failed
  /// row. Queued-but-not-started jobs are skipped naturally by the
  /// drainer's `if (job.token.isCancelled) continue;` check, and the
  /// Failed row is already in place.
  ///
  /// No-op when called with an unknown id, on a non-Pending record
  /// (Posted or Failed), or after [dispose].
  void cancelUpload(String entryId) {
    if (_isDisposed) return;
    for (final scope in _scopes.values) {
      final idx = scope.pending.indexWhere((r) => r.id == entryId);
      if (idx < 0) continue;
      final record = scope.pending[idx];
      if (record is! _Pending) return;
      scope.pending[idx] = _Failed(
        id: entryId,
        filename: record.filename,
        message: 'Upload cancelled.',
      );
      _emit(scope);
      record.cancelToken.cancel('user');
      return;
    }
  }

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
  // Deletion
  // --------------------------------------------------------

  /// Deletes [filename] from [roomId]'s uploads. Never completes with an
  /// error.
  ///
  /// The file shows as deleting until the server answers, and a second
  /// delete of it meanwhile is ignored. A 404 counts as deleted: the server
  /// answers a delete with it only when the room has no upload by that
  /// name, because, unlike a list fetch, a delete checks no read access. A
  /// deleted file leaves the list at once and a refresh follows. Any other
  /// failure keeps the file listed and adds a failed row saying why. A
  /// delete cancelled by [dispose] or by the session ending says nothing.
  Future<void> deleteRoomUpload({
    required String roomId,
    required String filename,
  }) async {
    if (_isDisposed) return;
    final scope = _scope(_roomKey(roomId));
    if (scope.deleting.containsKey(filename)) return;
    final token = CancelToken();
    scope.deleting[filename] = token;
    _emit(scope);

    try {
      await _api.deleteRoomUpload(roomId, filename, cancelToken: token);
    } on NotFoundException {
      // Deleted already, which is what the user asked for.
    } on CancelledException {
      if (_isDisposed) return;
      scope.deleting.remove(filename);
      _emit(scope);
      return;
    } on Object catch (error, stackTrace) {
      if (_isDisposed) return;
      scope.deleting.remove(filename);
      _recordDeleteFailure(scope, roomId, filename, error, stackTrace);
      // After the failed row, as for an upload, so a listener reacting to
      // the session flip sees a consistent tracker.
      if (error is AuthException) _auth.markSessionExpired();
      return;
    }
    if (_isDisposed) return;
    scope.deleting.remove(filename);
    final persisted = scope.persisted;
    if (persisted != null) {
      scope.persisted = [
        for (final f in persisted)
          if (f.filename != filename) f,
      ];
    }
    _emit(scope);
    unawaited(refreshRoom(roomId));
  }

  void _recordDeleteFailure(
    _ScopeState scope,
    String roomId,
    String filename,
    Object error,
    StackTrace stackTrace,
  ) {
    final statusCode = switch (error) {
      ApiException(:final statusCode) => statusCode,
      PermissionDeniedException(:final statusCode) => statusCode,
      AuthException(:final statusCode) => statusCode,
      _ => null,
    };
    // The status is kept, because the type alone cannot tell a server fault
    // from an installation without an upload path.
    final attributes = {
      'roomId': roomId,
      'filename': filename,
      if (statusCode != null) 'statusCode': statusCode,
    };
    if (error is SoliplexException) {
      // Attached whole: what a client exception carries is the server's
      // written reason, a host or URL, a file name and a status, none secret.
      _logger.warning(
        'Room upload delete failed',
        error: error,
        attributes: attributes,
      );
    } else {
      // Described, not attached: an unexpected error's text is whatever its
      // thrower put there.
      _logger.error(
        'Unexpected error during a room upload delete',
        attributes: {...attributes, 'failure': describeFailure(error)},
        stackTrace: stackTrace,
      );
    }
    scope.pending.add(_Failed(
      id: 'upload-${_nextId++}',
      filename: filename,
      message: deleteErrorMessage(error),
    ));
    _emit(scope);
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
          PersistedUpload(
            filename: f.filename,
            url: f.url,
            isDeleting: scope.deleting.containsKey(f.filename),
          ),
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
    _authUnsub?.call();
    _authUnsub = null;
    for (final scope in _scopes.values) {
      // Cancel both in-flight POSTs and queued-but-not-started jobs.
      // Each queued job's token is the same CancelToken instance stored
      // on its `_Pending` record, so this loop cancels both paths.
      // The drain loop sees `_isDisposed` and exits without invoking
      // any remaining queued jobs.
      for (final record in scope.pending) {
        if (record is _Pending) {
          record.cancelToken.cancel('disposed');
        }
      }
      scope.dispose();
    }
    _queue.clear();
    _scopes.clear();
  }

  /// Cancels all in-flight and queued uploads, and every delete in
  /// flight, when the auth session leaves [ActiveSession]. The route
  /// guard navigates the user away; this stops their HTTP work so it
  /// doesn't reconnect-loop against a dead token.
  ///
  /// Walking `scope.pending` covers both states because each queued
  /// job's [_QueuedJob.token] is the same [CancelToken] instance as the
  /// matching `_Pending.cancelToken`. The drain loop skips queued jobs
  /// whose token is cancelled (`_drain`'s `isCancelled` check).
  void _onAuthChanged(SessionState state) {
    if (_isDisposed) return;
    if (state is ActiveSession) return;
    for (final scope in _scopes.values) {
      for (final record in scope.pending) {
        if (record is _Pending) {
          record.cancelToken.cancel('auth expired');
        }
      }
      for (final token in scope.deleting.values) {
        token.cancel('auth expired');
      }
    }
  }
}
