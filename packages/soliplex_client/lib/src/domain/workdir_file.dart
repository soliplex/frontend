import 'package:meta/meta.dart';

/// A file anywhere in a thread's sandbox workspace.
///
/// Validation of [filename] (non-empty, a relative POSIX path with no empty,
/// `.` or `..` segments, no NUL bytes) is enforced at parse time by the
/// mapper, not in this constructor.
@immutable
class WorkdirFile {
  /// Creates a workdir file entry.
  const WorkdirFile({
    required this.filename,
    required this.url,
    this.modifiedAt,
    this.sizeBytes,
  });

  /// The file's path relative to the workspace root, as written by the agent
  /// (`notes.txt`, `dir/file.txt`).
  final String filename;

  /// The last segment of [filename]: `file.txt` for
  /// `dir/file.txt`.
  String get basename => filename.substring(filename.lastIndexOf('/') + 1);

  /// The directories above the file (`dir/sub` for
  /// `dir/sub/file.txt`), or `null` for a file at the workspace root.
  String? get directory {
    final slash = filename.lastIndexOf('/');
    return slash == -1 ? null : filename.substring(0, slash);
  }

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
    return other is WorkdirFile &&
        other.filename == filename &&
        other.url == url &&
        other.modifiedAt == modifiedAt &&
        other.sizeBytes == sizeBytes;
  }

  @override
  int get hashCode => Object.hash(filename, url, modifiedAt, sizeBytes);

  @override
  String toString() => 'WorkdirFile(filename: $filename, url: $url, '
      'modifiedAt: $modifiedAt, sizeBytes: $sizeBytes)';
}
