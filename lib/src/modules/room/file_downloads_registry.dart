import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../auth/server_entry.dart';
import 'file_downloads.dart';
import 'per_server_cache.dart';
import 'workdir_controller.dart' show warnWorkdirFetchFailed;

final _logger = LogManager.instance.getLogger('workdir_files');

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
  // file_picker 11.0.3 throws on web for empty bytes or a name with no
  // extension (`Makefile`, `.env`), so such a download reports failed. On
  // desktop it writes nothing for empty bytes, yet returns the chosen path,
  // so an empty file reports success with nothing saved.
  return FilePicker.saveFile(fileName: fileName, bytes: bytes);
}

/// Each thread's file downloads, per server and room.
///
/// The room module keeps it, not the room screen, so a download outlives the
/// visit to its room that started it: coming back shows it under way or its
/// outcome, and a file starts no second download. Its downloads are cleared
/// when their server is removed or a different user signs in on it.
///
/// [saveFile] and [isWeb] are injected so tests can drive both branches of
/// the cancel logic (web returns null on success, native returns null on
/// cancel) without spinning up real platform plugins.
class FileDownloadsRegistry {
  FileDownloadsRegistry({
    required ReadonlySignal<Map<String, ServerEntry>> servers,
    SaveFile saveFile = _defaultSaveFile,
    bool isWeb = kIsWeb,
  })  : _saveFile = saveFile,
        _isWeb = isWeb,
        _downloads = PerServerCache(
          servers: servers,
          disposeValue: (downloads) => downloads.dispose(),
          what: 'file downloads',
        );

  final SaveFile _saveFile;
  final bool _isWeb;
  final PerServerCache<(String, String), FileDownloads> _downloads;

  /// The downloads of [threadId] in [roomId] on [entry]'s server. Throws
  /// [StateError] once the registry is disposed.
  FileDownloads downloadsFor({
    required ServerEntry entry,
    required String roomId,
    required String threadId,
  }) =>
      _downloads.putIfAbsent(entry.serverId, (roomId, threadId), () {
        late final FileDownloads downloads;
        return downloads = FileDownloads(
          (file) => downloadWorkdirFile(
            api: entry.connection.api,
            roomId: roomId,
            threadId: threadId,
            file: file,
            saveFile: _saveFile,
            isWeb: _isWeb,
            isCleared: () => downloads.isDisposed,
          ),
        );
      });

  /// Clears [serverId]'s downloads, so a different user signing in on it
  /// starts with none of the prior user's.
  void evictServer(String serverId) => _downloads.evictServer(serverId);

  void dispose() => _downloads.dispose();
}

/// Downloads [file]'s bytes through the authenticated client and hands
/// them to the platform save dialog. Distinguishes user-cancel from
/// real failure so the caller can render the right inline feedback.
///
/// Saves nothing once [isCleared] says its downloads were cleared: the
/// server was removed or another user signed in on it, so whoever is there
/// now did not ask for the file.
Future<DownloadOutcome> downloadWorkdirFile({
  required SoliplexApi api,
  required String roomId,
  required String threadId,
  required WorkdirFile file,
  required SaveFile saveFile,
  required bool isWeb,
  required bool Function() isCleared,
}) async {
  _logger.debug(
    'workdir download start threadId=$threadId name=${file.filename}',
  );
  final Uint8List bytes;
  try {
    bytes = await api.getThreadWorkdirFile(
      roomId,
      threadId,
      file.filename,
    );
  } catch (e, st) {
    warnWorkdirFetchFailed(_logger, 'download', threadId, file, e, st);
    return DownloadOutcome.failed;
  }
  if (isCleared()) {
    _logger.debug(
      'workdir download dropped, its downloads cleared threadId=$threadId '
      'name=${file.filename}',
    );
    return DownloadOutcome.cancelled;
  }
  try {
    final path = await saveFile(fileName: file.basename, bytes: bytes);
    if (!isWeb && path == null) {
      _logger.debug(
        'workdir file download cancelled threadId=$threadId '
        'name=${file.filename}',
      );
      return DownloadOutcome.cancelled;
    }
    if (isWeb) {
      // The browser triggers the download immediately and saveFile
      // returns null even on success; whether the file actually reached
      // the user's downloads folder is unverifiable from here.
      _logger.debug(
        'workdir file download web-triggered threadId=$threadId '
        'name=${file.filename} bytes=${bytes.length}',
      );
    } else {
      _logger.debug(
        'workdir file download saved threadId=$threadId '
        'name=${file.filename} bytes=${bytes.length}',
      );
    }
    return DownloadOutcome.success;
  } catch (e, st) {
    // Attached whole: a save failure is the platform's, the save dialog's
    // error, the web saver's fixed-text refusal of an empty file or a name
    // with no extension or, when writing the file failed, one naming the
    // local path it could not write. None holds a credential.
    _logger.warning(
      'workdir download save failed threadId=$threadId',
      error: e,
      stackTrace: st,
      attributes: {'filename': file.filename},
    );
    return DownloadOutcome.failed;
  }
}
