import 'package:meta/meta.dart';
import 'package:soliplex_client/src/domain/served_file.dart';

/// A file persisted in the backend's upload directory for a room or
/// thread.
///
/// Returned by `GET /uploads/{room_id}` and
/// `GET /uploads/{room_id}/{thread_id}`.
@immutable
class FileUpload implements ServedFile {
  /// Creates a file upload entry.
  const FileUpload({
    required this.filename,
    required this.url,
    this.modifiedAt,
    this.sizeBytes,
  });

  /// User-visible filename as stored by the backend. The backend lists only
  /// the files directly in an upload directory, so this is one path segment;
  /// neither the mapper nor this constructor checks it.
  @override
  final String filename;

  /// [filename], as the backend lists an upload by one path segment.
  @override
  String get basename => filename;

  /// Always `null`: an upload sits directly in its room's or thread's upload
  /// directory.
  @override
  String? get directory => null;

  /// URL for downloading the file.
  final Uri url;

  /// When the file was last modified, in UTC, or `null` when the backend did
  /// not report a usable value.
  final DateTime? modifiedAt;

  /// The file's size in bytes, or `null` when the backend did not report a
  /// usable value.
  @override
  final int? sizeBytes;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FileUpload &&
        other.filename == filename &&
        other.url == url &&
        other.modifiedAt == modifiedAt &&
        other.sizeBytes == sizeBytes;
  }

  @override
  int get hashCode => Object.hash(filename, url, modifiedAt, sizeBytes);

  @override
  String toString() => 'FileUpload(filename: $filename, url: $url, '
      'modifiedAt: $modifiedAt, sizeBytes: $sizeBytes)';
}
