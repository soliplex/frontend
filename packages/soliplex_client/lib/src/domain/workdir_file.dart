import 'package:meta/meta.dart';

/// A file written by the agent into the run working directory.
///
/// Validation of [filename] (non-empty, no path separators, no NUL bytes)
/// is enforced at parse time by the mapper, not in this constructor.
@immutable
class WorkdirFile {
  /// Creates a workdir file entry.
  const WorkdirFile({required this.filename, required this.url});

  /// User-visible filename as written by the agent into the workdir.
  final String filename;

  /// URL for downloading the file.
  final Uri url;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WorkdirFile &&
        other.filename == filename &&
        other.url == url;
  }

  @override
  int get hashCode => Object.hash(filename, url);

  @override
  String toString() => 'WorkdirFile(filename: $filename, url: $url)';
}
