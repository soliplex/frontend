import 'dart:typed_data';

import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final _logger = LogManager.instance.getLogger('room_files');

/// Where a [ServedFile] is fetched from: a thread's workspace, a room's
/// uploads or a thread's uploads. Equal sources hold the same files.
sealed class FileSource {
  const FileSource({required this.roomId});

  final String roomId;

  /// Fetches the bytes of the file this source lists as [filename].
  Future<Uint8List> fetch(SoliplexApi api, String filename);

  /// Names [file], fetched from this source, in a log record's attributes.
  Map<String, Object> logAttributesOf(ServedFile file) =>
      {..._sourceAttributes, 'filename': file.filename};

  /// Names this source in a log record's attributes.
  Map<String, Object> get _sourceAttributes;
}

final class WorkspaceFileSource extends FileSource {
  const WorkspaceFileSource({required super.roomId, required this.threadId});

  final String threadId;

  @override
  Future<Uint8List> fetch(SoliplexApi api, String filename) =>
      api.getThreadWorkdirFile(roomId, threadId, filename);

  @override
  Map<String, Object> get _sourceAttributes =>
      {'source': 'workspace', 'roomId': roomId, 'threadId': threadId};

  @override
  bool operator ==(Object other) =>
      other is WorkspaceFileSource &&
      other.roomId == roomId &&
      other.threadId == threadId;

  @override
  int get hashCode => Object.hash(WorkspaceFileSource, roomId, threadId);
}

final class RoomUploadSource extends FileSource {
  const RoomUploadSource({required super.roomId});

  @override
  Future<Uint8List> fetch(SoliplexApi api, String filename) =>
      api.getRoomUpload(roomId, filename);

  @override
  Map<String, Object> get _sourceAttributes =>
      {'source': 'roomUploads', 'roomId': roomId};

  @override
  bool operator ==(Object other) =>
      other is RoomUploadSource && other.roomId == roomId;

  @override
  int get hashCode => Object.hash(RoomUploadSource, roomId);
}

final class ThreadUploadSource extends FileSource {
  const ThreadUploadSource({required super.roomId, required this.threadId});

  final String threadId;

  @override
  Future<Uint8List> fetch(SoliplexApi api, String filename) =>
      api.getThreadUpload(roomId, threadId, filename);

  @override
  Map<String, Object> get _sourceAttributes =>
      {'source': 'threadUploads', 'roomId': roomId, 'threadId': threadId};

  @override
  bool operator ==(Object other) =>
      other is ThreadUploadSource &&
      other.roomId == roomId &&
      other.threadId == threadId;

  @override
  int get hashCode => Object.hash(ThreadUploadSource, roomId, threadId);
}

/// Fetches [file]'s bytes from [source] for the in-app preview; the save
/// dialog is the download path.
///
/// [NotFoundException] is logged at debug and rethrown so the preview can
/// render its own "gone" state: the file being gone should not look like a
/// successful empty preview. Any other failure is logged as a warning and
/// rethrown.
Future<Uint8List> fetchFileBytes(
  SoliplexApi api,
  FileSource source,
  ServedFile file,
) async {
  final attributes = source.logAttributesOf(file);
  _logger.debug('file preview fetch start', attributes: attributes);
  try {
    final bytes = await source.fetch(api, file.filename);
    _logger.debug(
      'file fetched for preview',
      attributes: {...attributes, 'byteLength': bytes.length},
    );
    return bytes;
  } on NotFoundException {
    _logger.debug('file preview fetch 404', attributes: attributes);
    rethrow;
  } catch (e, st) {
    warnFileFetchFailed(
      _logger,
      purpose: 'preview',
      source: source,
      file: file,
      error: e,
      stackTrace: st,
    );
    rethrow;
  }
}

/// Logs a failed fetch of [file]'s bytes for [purpose] with the failure
/// whole, so the record keeps its status code and the server's reason.
void warnFileFetchFailed(
  Logger logger, {
  required String purpose,
  required FileSource source,
  required ServedFile file,
  required Object error,
  required StackTrace stackTrace,
}) {
  // A bodiless GET with the token in a header, so a failure can carry only
  // the URL path (room and thread ids, the file's name or path), a status
  // code, a host, or the answering server's JSON reason: a fixed
  // string or one naming the room, thread or file on the workdir and upload
  // routes, a status phrase from a proxy answering in their place. The
  // client's own ArgumentError for an empty or malformed argument names only
  // that argument and its value: an id, or the file's name or path.
  logger.warning(
    'file $purpose fetch failed',
    error: error,
    stackTrace: stackTrace,
    attributes: source.logAttributesOf(file),
  );
}

/// Why fetching a file to download or preview failed, as fixed text for the
/// user: the error's own message can carry backend text.
String fileFetchFailureReason(Object error) => switch (error) {
      // The server answers a 404 when the file is gone, and also when the
      // workspace is not served, the installation keeps no uploads, or the
      // user may not see the room or thread. The client cannot tell these
      // apart, so the text says only that the file is no longer available.
      NotFoundException() => "File isn't available anymore",
      NetworkException() => "Couldn't reach the server",
      AuthException() => 'Sign in again',
      PermissionDeniedException() => "You don't have access to this file",
      ApiException(:final statusCode) when statusCode >= 500 =>
        'Server is temporarily unavailable',
      ApiException() => "The server couldn't send the file",
      _ => 'Something went wrong',
    };
