import 'dart:async';
import 'dart:typed_data';

import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'workdir_files_status.dart';
import 'workspace_groups.dart';

class _ThreadFiles {
  final signal = Signal<WorkdirFilesStatus>(const WorkdirFilesLoading());
  final folderToggles = Signal<Map<String, bool>>(const {});
  CancelToken? fetchToken;

  void dispose() {
    fetchToken?.cancel('disposed');
    signal.dispose();
    folderToggles.dispose();
  }
}

/// Owns each thread's workspace listing and open folders, and fetches its
/// files' bytes for the preview, for one visit to a room.
class WorkdirController {
  WorkdirController({
    required SoliplexApi api,
    required String roomId,
    Logger? logger,
  })  : _api = api,
        _roomId = roomId,
        _logger = logger ?? LogManager.instance.getLogger('workdir_files');

  final SoliplexApi _api;
  final String _roomId;
  final Logger _logger;
  final _threads = <String, _ThreadFiles>{};
  bool _isDisposed = false;

  _ThreadFiles _thread(String threadId) {
    if (_isDisposed) throw StateError('WorkdirController has been disposed');
    return _threads.putIfAbsent(threadId, _ThreadFiles.new);
  }

  /// The thread's workspace listing. Starts [WorkdirFilesLoading]; call
  /// [refresh] to fetch.
  ReadonlySignal<WorkdirFilesStatus> files(String threadId) =>
      _thread(threadId).signal;

  /// The folders of the thread's listing the reader has opened or closed, by
  /// path from the workspace root, mapped to whether each is open. A folder
  /// not in it shows its default (see [isFolderExpanded]). Kept apart from
  /// the listing, so a refresh leaves it as the reader set it; it lasts as
  /// long as this controller.
  ReadonlySignal<Map<String, bool>> folderToggles(String threadId) =>
      _thread(threadId).folderToggles;

  /// Records that the reader opened or closed the thread's [folder], a path
  /// from the workspace root.
  void setFolderExpanded(
    String threadId,
    String folder, {
    required bool expanded,
  }) {
    final toggles = _thread(threadId).folderToggles;
    toggles.value = {...toggles.value, folder: expanded};
    _logger.debug(
      'workdir folder toggled threadId=$threadId folder=$folder '
      'expanded=$expanded',
    );
  }

  /// Closes the thread's [folders], paths from the workspace root.
  void closeFolders(String threadId, Iterable<String> folders) {
    final toggles = _thread(threadId).folderToggles;
    final closing = {for (final folder in folders) folder: false};
    toggles.value = {...toggles.value, ...closing};
    _logger.debug(
      'workdir folders closed threadId=$threadId folders=${closing.length}',
    );
  }

  /// Opens every folder above each of [files], so a reader shown them finds
  /// them whatever they closed before. Folders already open by
  /// [isFolderExpanded] are left untouched, so the panel does not rebuild for
  /// nothing. That test takes each folder's own depth: the deepest folder of
  /// a merged top-level chain, such as `raw/archive`, counts as nested and so
  /// closed unless toggled, and is recorded open though its row shows open.
  void openFoldersOf(String threadId, Iterable<WorkdirFile> files) {
    final toggles = _thread(threadId).folderToggles;
    final folders = {
      for (final file in files)
        for (final (depth, folder) in ancestorsOf(file).indexed)
          if (!isFolderExpanded(toggles.value, folder, topLevel: depth == 0))
            folder,
    };
    if (folders.isEmpty) return;
    toggles.value = {
      ...toggles.value,
      for (final folder in folders) folder: true,
    };
    _logger.debug(
      'workdir folders opened to show files threadId=$threadId '
      'folders=${folders.length}',
    );
  }

  /// Fetches the thread's listing, cancelling any fetch still in flight for
  /// it. A failure or 404 after a list has loaded keeps that list: the
  /// workspace is never deleted, so the list on screen is still the best
  /// answer. A 404 before anything loaded is an empty list, because it is
  /// also how a server without workspaces answers. A retry after a failure
  /// stays [WorkdirFilesFailed], marked retrying, so the section that offered
  /// the retry is still on screen to show its result.
  Future<void> refresh(String threadId) async {
    if (_isDisposed) return;
    final entry = _thread(threadId);
    entry.fetchToken?.cancel('re-fetch');
    final token = CancelToken();
    entry.fetchToken = token;
    final current = entry.signal.value;
    if (current is WorkdirFilesFailed && !current.retrying) {
      entry.signal.value = WorkdirFilesFailed(current.error, retrying: true);
    }

    try {
      final listed = await _api.getThreadWorkdirFiles(
        _roomId,
        threadId,
        cancelToken: token,
      );
      if (token.isCancelled) return;
      entry.fetchToken = null;
      _emitLoaded(entry, listed);
      _logger.debug(
        'workdir list loaded threadId=$threadId count=${listed.length}',
      );
    } on NotFoundException {
      if (token.isCancelled) return;
      entry.fetchToken = null;
      if (entry.signal.value is WorkdirFilesLoaded) {
        // The steady state on a server that keeps no workspaces, so a trace,
        // not a warning.
        _logger.debug(
          'workdir list 404 after a load; keeping it threadId=$threadId',
        );
        return;
      }
      _emitLoaded(entry, const []);
      _logger.debug('workdir list 404 before a load; empty threadId=$threadId');
    } catch (e, st) {
      if (token.isCancelled) {
        _logger.debug('workdir list fetch cancelled threadId=$threadId');
        return;
      }
      entry.fetchToken = null;
      // A bodiless GET with the token in a header, so a failure can carry only
      // the URL path (room and thread ids), a status code, a host, or the
      // answering server's JSON message field: a fixed string on the workdir
      // routes, a status phrase from a proxy answering in their place. The
      // transport wraps body-decode failures, so no payload window reaches
      // here.
      _logger.warning(
        'workdir list refresh failed threadId=$threadId',
        error: e,
        stackTrace: st,
      );
      if (entry.signal.value is WorkdirFilesLoaded) return;
      entry.signal.value = WorkdirFilesFailed(e);
    }
  }

  void _emitLoaded(_ThreadFiles entry, List<WorkdirFile> listed) {
    final files = [...listed]..sort((a, b) => a.filename.compareTo(b.filename));
    entry.signal.value = WorkdirFilesLoaded(files);
  }

  /// Fetches the raw bytes for [file] without writing them to disk. Used
  /// by the in-app preview path; the save dialog is the download path.
  ///
  /// [NotFoundException] is logged at debug and rethrown so the preview
  /// FutureBuilder can render its own error state; "the file is gone" should
  /// not look like a successful empty preview.
  Future<Uint8List> fetchFileBytes(String threadId, WorkdirFile file) async {
    _logger.debug(
      'workdir preview fetch start threadId=$threadId name=${file.filename}',
    );
    try {
      final bytes = await _api.getThreadWorkdirFile(
        _roomId,
        threadId,
        file.filename,
      );
      _logger.debug(
        'workdir file fetched for preview threadId=$threadId '
        'name=${file.filename} bytes=${bytes.length}',
      );
      return bytes;
    } on NotFoundException {
      _logger.debug(
        'workdir preview fetch 404 threadId=$threadId name=${file.filename}',
      );
      rethrow;
    } catch (e, st) {
      warnWorkdirFetchFailed(
        _logger,
        purpose: 'preview',
        roomId: _roomId,
        threadId: threadId,
        file: file,
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  void dispose() {
    _isDisposed = true;
    for (final entry in _threads.values) {
      entry.dispose();
    }
    _threads.clear();
  }
}

/// Logs a failed fetch of [file]'s bytes for [purpose] with the failure
/// whole, so the record keeps its status code and the server's reason.
void warnWorkdirFetchFailed(
  Logger logger, {
  required String purpose,
  required String roomId,
  required String threadId,
  required WorkdirFile file,
  required Object error,
  required StackTrace stackTrace,
}) {
  // A bodiless GET with the token in a header, so a failure can carry only
  // the URL path (room and thread ids, the file's path), a status code, a
  // host, or the answering server's JSON message field: a fixed string on
  // the workdir routes, a status phrase from a proxy answering in their
  // place. The client's own ArgumentError for an empty or malformed argument
  // names only that argument and its value: an id or the file's path.
  logger.warning(
    'workdir $purpose fetch failed roomId=$roomId threadId=$threadId',
    error: error,
    stackTrace: stackTrace,
    attributes: {'filename': file.filename},
  );
}
