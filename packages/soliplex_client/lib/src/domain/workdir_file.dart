import 'package:meta/meta.dart';

/// A file written by the agent into the run working directory.
///
/// Returned by `GET /workdirs/{room_id}/thread/{thread_id}/{run_id}`.
@immutable
class WorkdirFile {
  /// Creates a workdir file entry.
  const WorkdirFile({required this.filename, required this.url});

  /// User-visible filename as written by the agent.
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
