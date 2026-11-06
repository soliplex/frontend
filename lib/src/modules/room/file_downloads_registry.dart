import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../auth/auth_tokens.dart' show NoSession;
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

/// Each thread's file downloads, per server entry and room.
///
/// The room module keeps it, not the room screen, so a download outlives the
/// visit to its room that started it: coming back shows it under way or its
/// outcome, and a file starts no second download. Its downloads are cleared
/// when their server is removed (or removed and re-added), when a different
/// user signs in on it, and when the registry is disposed.
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
        );

  final SaveFile _saveFile;
  final bool _isWeb;
  final PerServerCache<(String, String), FileDownloads> _downloads;

  /// The downloads of [threadId] in [roomId] for [entry]. Throws
  /// [StateError] once the registry is disposed.
  FileDownloads downloadsFor({
    required ServerEntry entry,
    required String roomId,
    required String threadId,
  }) =>
      _downloads.putIfAbsent(
        entry,
        (roomId, threadId),
        () => FileDownloads((file, isCleared) async {
          // Signing out keeps a download from saving, even if the user signs
          // back in before it would have saved. A server not signed in, as
          // with no auth, has no sign-out to watch for.
          var signedIn = false;
          var signedOut = false;
          final unsubscribe = entry.auth.session.subscribe((session) {
            if (session is! NoSession) {
              signedIn = true;
            } else if (signedIn) {
              signedOut = true;
            }
          });
          try {
            return await downloadWorkdirFile(
              api: entry.connection.api,
              roomId: roomId,
              threadId: threadId,
              file: file,
              saveFile: _saveFile,
              isWeb: _isWeb,
              isUnwanted: () => isCleared() || signedOut,
            );
          } finally {
            unsubscribe();
          }
        }),
      );

  /// Clears [serverId]'s downloads, so a different user signing in on it
  /// starts with none of the prior user's.
  void evictServer(String serverId) => _downloads.evictServer(serverId);

  void dispose() => _downloads.dispose();
}

/// Downloads [file]'s bytes through the authenticated client and hands
/// them to the platform save dialog. Distinguishes user-cancel from
/// real failure so the caller can render the right inline feedback.
///
/// Once [isUnwanted] says nobody is left to want the file, it opens no save
/// dialog and reports no failure, returning [DownloadOutcome.cancelled]: its
/// downloads were cleared (see [FileDownloadsRegistry]), or its user signed
/// out while it was fetched. A dialog already open saves whatever its user
/// chooses.
Future<DownloadOutcome> downloadWorkdirFile({
  required SoliplexApi api,
  required String roomId,
  required String threadId,
  required WorkdirFile file,
  required SaveFile saveFile,
  required bool isWeb,
  required bool Function() isUnwanted,
}) async {
  _logger.debug(
    'workdir download start roomId=$roomId threadId=$threadId '
    'name=${file.filename}',
  );
  final Uint8List bytes;
  try {
    bytes = await api.getThreadWorkdirFile(
      roomId,
      threadId,
      file.filename,
    );
  } catch (e, st) {
    // A fetch failing once nobody wants the file is no failure to report.
    if (isUnwanted()) return _dropped(roomId, threadId, file);
    warnWorkdirFetchFailed(
      _logger,
      purpose: 'download',
      roomId: roomId,
      threadId: threadId,
      file: file,
      error: e,
      stackTrace: st,
    );
    return DownloadOutcome.failed;
  }
  if (isUnwanted()) return _dropped(roomId, threadId, file);
  try {
    final path = await saveFile(fileName: file.basename, bytes: bytes);
    if (!isWeb && path == null) {
      _logger.debug(
        'workdir file download cancelled roomId=$roomId threadId=$threadId '
        'name=${file.filename}',
      );
      return DownloadOutcome.cancelled;
    }
    if (isWeb) {
      // The browser triggers the download immediately and saveFile
      // returns null even on success; whether the file actually reached
      // the user's downloads folder is unverifiable from here.
      _logger.debug(
        'workdir file download web-triggered roomId=$roomId '
        'threadId=$threadId '
        'name=${file.filename} bytes=${bytes.length}',
      );
    } else {
      _logger.debug(
        'workdir file download saved roomId=$roomId threadId=$threadId '
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
      'workdir download save failed roomId=$roomId threadId=$threadId',
      error: e,
      stackTrace: st,
      attributes: {'filename': file.filename},
    );
    return DownloadOutcome.failed;
  }
}

DownloadOutcome _dropped(String roomId, String threadId, WorkdirFile file) {
  _logger.debug(
    'workdir download dropped, nobody left to want it '
    'roomId=$roomId threadId=$threadId name=${file.filename}',
  );
  return DownloadOutcome.cancelled;
}
