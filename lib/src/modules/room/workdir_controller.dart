import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'ui/workdir_files_section.dart' show DownloadOutcome;

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

/// Owns the per-thread cache for `getRunWorkdirFiles` and the download
/// flow that pipes bytes from the API into the platform save dialog.
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
  final _cache = <String, Future<List<WorkdirFile>>>{};

  /// Lists the files an agent run wrote to its workdir. Caches the
  /// pending future so SliverList recycling doesn't re-fetch on
  /// scroll-back.
  ///
  /// The 404 returned when the backend has no sandbox configured is
  /// converted to an empty list so chat tiles silently collapse the
  /// section. Any other failure evicts the cached entry and rethrows so
  /// the UI's [FutureBuilder] can show its retry row.
  Future<List<WorkdirFile>> fetchFiles(String threadId, String runId) {
    final key = '$threadId/$runId';
    return _cache.putIfAbsent(key, () async {
      _logger.debug('workdir fetch start runId=$runId');
      try {
        final files = await _api.getRunWorkdirFiles(_roomId, threadId, runId);
        _logger.debug('workdir fetch ok runId=$runId n=${files.length}');
        return files;
      } on NotFoundException {
        _logger.debug('workdir fetch 404 runId=$runId');
        return const [];
      } catch (e, st) {
        _logger.warning(
          'workdir fetch failed runId=$runId',
          error: e,
          stackTrace: st,
        );
        _cache.remove(key);
        rethrow;
      }
    });
  }

  /// Downloads [file]'s bytes through the authenticated client and hands
  /// them to the platform save dialog. Distinguishes user-cancel from
  /// real failure so the caller can render the right inline feedback.
  Future<DownloadOutcome> download(
    String threadId,
    String runId,
    WorkdirFile file,
  ) async {
    _logger.debug(
      'workdir download start runId=$runId name=${file.filename}',
    );
    try {
      final bytes = await _api.getRunWorkdirFile(
        _roomId,
        threadId,
        runId,
        file.filename,
      );
      final path = await _saveFile(fileName: file.filename, bytes: bytes);
      if (!_isWeb && path == null) {
        _logger.debug('workdir download cancelled runId=$runId');
        return DownloadOutcome.cancelled;
      }
      if (_isWeb) {
        // The browser triggers the download immediately and saveFile
        // returns null even on success; whether the file actually reached
        // the user's downloads folder is unverifiable from here.
        _logger.debug(
          'workdir download web-triggered runId=$runId bytes=${bytes.length}',
        );
      } else {
        _logger.debug(
          'workdir download ok runId=$runId bytes=${bytes.length}',
        );
      }
      return DownloadOutcome.success;
    } catch (e, st) {
      _logger.warning(
        'workdir download failed runId=$runId',
        error: e,
        stackTrace: st,
      );
      return DownloadOutcome.failed;
    }
  }

  /// Drops every cached fetch result. Call when the user switches away
  /// from a thread so the next thread starts with a clean cache.
  void clearCache() => _cache.clear();
}
