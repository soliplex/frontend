import 'package:meta/meta.dart';

/// A file persisted in the backend's upload directory for a room or
/// thread.
///
/// Returned by `GET /uploads/{room_id}` and
/// `GET /uploads/{room_id}/{thread_id}`.
@immutable
class FileUpload {
  /// Creates a file upload entry.
  const FileUpload({
    required this.filename,
    required this.url,
    this.modifiedAt,
    this.sizeBytes,
  });

  /// User-visible filename as stored by the backend.
  final String filename;

  /// URL for downloading the file.
  final Uri url;

  /// When the file was last modified, in UTC, or `null` when the backend did
  /// not report a usable value.
  final DateTime? modifiedAt;

  /// The file's size in bytes, or `null` when the backend did not report a
  /// usable value.
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
