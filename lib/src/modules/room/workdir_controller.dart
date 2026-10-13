import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'ui/workdir_files.dart' show DownloadOutcome;
import 'workdir_files_status.dart';

/// Save the [bytes] under [fileName], typically by opening the platform
/// save dialog. Returns the chosen path on success, or `null` if the user
/// cancelled. On web the browser triggers the download directly and the
/// returned path is always `null`.
typedef SaveFile = Future<String?> Function({
  required String fileName,
  required Uint8List bytes,
});

Future<String?> _defaultSaveFile({
  required String fileName,
  required Uint8List bytes,
}) {
  return FilePicker.saveFile(fileName: fileName, bytes: bytes);
}

class _ThreadFiles {
  final signal = Signal<WorkdirFilesStatus>(const WorkdirFilesLoading());
  CancelToken? fetchToken;

  void dispose() {
    fetchToken?.cancel('disposed');
    signal.dispose();
  }
}

/// Owns each thread's workspace listing and the download flow that pipes
/// bytes from the API into the platform save dialog.
///
/// Constructor parameters are injected so tests can drive both branches
/// of the cancel logic (web returns null on success, native returns null
/// on cancel) without spinning up real platform plugins.
class WorkdirController {
  WorkdirController({
    required SoliplexApi api,
    required String roomId,
    Logger? logger,
    SaveFile? saveFile,
    bool isWeb = kIsWeb,
  })  : _api = api,
        _roomId = roomId,
        _logger = logger ?? LogManager.instance.getLogger('workdir_files'),
        _saveFile = saveFile ?? _defaultSaveFile,
        _isWeb = isWeb;

  final SoliplexApi _api;
  final String _roomId;
  final Logger _logger;
  final SaveFile _saveFile;
  final bool _isWeb;
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
      if (token.isCancelled || _isDisposed) return;
      entry.fetchToken = null;
      _emitLoaded(entry, listed);
    } on NotFoundException {
      if (token.isCancelled || _isDisposed) return;
      entry.fetchToken = null;
      if (entry.signal.value is WorkdirFilesLoaded) {
        // The steady state in a room without a sandbox, so a trace, not a
        // warning.
        _logger.debug(
          'workdir list 404 after a load; keeping it threadId=$threadId',
        );
        return;
      }
      _emitLoaded(entry, const []);
    } catch (e, st) {
      if (token.isCancelled || _isDisposed) return;
      entry.fetchToken = null;
      _logger.warning(
        'workdir list refresh failed threadId=$threadId',
        stackTrace: st,
        attributes: {'failure': describeFailure(e)},
      );
      if (entry.signal.value is WorkdirFilesLoaded) return;
      entry.signal.value = WorkdirFilesFailed(e);
    }
  }

  void _emitLoaded(_ThreadFiles entry, List<WorkdirFile> listed) {
    final files = [...listed]..sort((a, b) => a.filename.compareTo(b.filename));
    entry.signal.value = WorkdirFilesLoaded(files);
  }

  /// Downloads [file]'s bytes through the authenticated client and hands
  /// them to the platform save dialog. Distinguishes user-cancel from
  /// real failure so the caller can render the right inline feedback.
  Future<DownloadOutcome> downloadFile(
    String threadId,
    WorkdirFile file,
  ) async {
    _logger.debug(
      'workdir download start threadId=$threadId name=${file.filename}',
    );
    try {
      final bytes = await _api.getThreadWorkdirFile(
        _roomId,
        threadId,
        file.filename,
      );
      final path = await _saveFile(fileName: file.filename, bytes: bytes);
      if (!_isWeb && path == null) {
        _logger.debug('workdir download cancelled threadId=$threadId');
        return DownloadOutcome.cancelled;
      }
      if (_isWeb) {
        // The browser triggers the download immediately and saveFile
        // returns null even on success; whether the file actually reached
        // the user's downloads folder is unverifiable from here.
        _logger.debug(
          'workdir download web-triggered threadId=$threadId '
          'bytes=${bytes.length}',
        );
      } else {
        _logger.debug(
          'workdir download ok threadId=$threadId bytes=${bytes.length}',
        );
      }
      return DownloadOutcome.success;
    } catch (e, st) {
      _logger.warning(
        'workdir download failed threadId=$threadId',
        stackTrace: st,
        attributes: {
          'failure': describeFailure(e),
          'filename': file.filename,
        },
      );
      return DownloadOutcome.failed;
    }
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
        'workdir preview fetch ok threadId=$threadId bytes=${bytes.length}',
      );
      return bytes;
    } on NotFoundException {
      _logger.debug(
        'workdir preview fetch 404 threadId=$threadId name=${file.filename}',
      );
      rethrow;
    } catch (e, st) {
      _logger.warning(
        'workdir preview fetch failed threadId=$threadId',
        stackTrace: st,
        attributes: {
          'failure': describeFailure(e),
          'filename': file.filename,
        },
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
