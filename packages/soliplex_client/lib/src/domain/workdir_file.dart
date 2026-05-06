import 'package:meta/meta.dart';

/// A file written by the agent into the run working directory.
@immutable
class WorkdirFile {
  /// Throws if [filename] is empty, contains a path separator, or contains
  /// a NUL byte.
  WorkdirFile({required this.filename})
      : assert(filename.isNotEmpty, 'filename must be non-empty'),
        assert(
          !filename.contains('/'),
          'filename must not contain path separators',
        ),
        assert(
          !filename.contains('\x00'),
          'filename must not contain NUL bytes',
        );

  /// Filename as written by the agent into the workdir. Always non-empty
  /// and free of path separators or NUL bytes.
  final String filename;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WorkdirFile && other.filename == filename;
  }

  @override
  int get hashCode => filename.hashCode;

  @override
  String toString() => 'WorkdirFile(filename: $filename)';
}
