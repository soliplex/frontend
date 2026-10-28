import 'package:soliplex_client/soliplex_client.dart' show WorkdirFile;

/// Directories that tools, not the agent's task, fill: Git's repository and
/// CPython's bytecode cache. The names are fixed by those tools.
const _toolingDirectories = {'.git', '__pycache__'};

/// Splits a workspace listing into its root files and one folder per first
/// path segment, each in listing order.
({
  List<WorkdirFile> files,
  List<({String name, List<WorkdirFile> files})> folders,
}) groupByFirstFolder(List<WorkdirFile> listing) {
  final files = <WorkdirFile>[];
  final folders = <String, List<WorkdirFile>>{};
  for (final file in listing) {
    final slash = file.filename.indexOf('/');
    if (slash == -1) {
      files.add(file);
    } else {
      (folders[file.filename.substring(0, slash)] ??= []).add(file);
    }
  }
  return (
    files: files,
    folders: [
      for (final MapEntry(:key, :value) in folders.entries)
        (name: key, files: value),
    ],
  );
}

/// The directory of [file] below the first-level [folder] that holds it, or
/// `null` for a file directly in [folder].
String? directoryWithin(WorkdirFile file, String folder) {
  final directory = file.directory;
  return directory == folder ? null : directory?.substring(folder.length + 1);
}

/// Whether the first-level [folder] starts collapsed: a tooling directory
/// is rarely what a reader opens the workspace for.
bool startsCollapsed(String folder) => _toolingDirectories.contains(folder);

/// Whether [path] lies in, or names, a tooling directory at any depth.
bool isToolingPath(String path) =>
    path.split('/').any(_toolingDirectories.contains);
