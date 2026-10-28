import 'package:soliplex_client/soliplex_client.dart' show WorkdirFile;

/// Directories that tools, not the agent's task, fill: Git's repository and
/// CPython's bytecode cache. The names are fixed by those tools.
const _toolingDirectories = {'.git', '__pycache__'};

/// Splits a workspace listing into its root files and one folder per first
/// path segment: files in listing order, and folders in the order they first
/// appear, except that the folders that [startsCollapsed] come last. They
/// hold no output a reader looks for, so they stay out of the way of the
/// folders that do.
({
  List<WorkdirFile> files,
  List<({String name, List<WorkdirFile> files})> folders,
}) groupByFirstFolder(List<WorkdirFile> listing) {
  final files = <WorkdirFile>[];
  final folders = <String, List<WorkdirFile>>{};
  for (final file in listing) {
    if (firstFolderOf(file) case final folder?) {
      (folders[folder] ??= []).add(file);
    } else {
      files.add(file);
    }
  }
  return (
    files: files,
    folders: [
      for (final MapEntry(:key, :value) in folders.entries)
        if (!startsCollapsed(key)) (name: key, files: value),
      for (final MapEntry(:key, :value) in folders.entries)
        if (startsCollapsed(key)) (name: key, files: value),
    ],
  );
}

/// The first-level folder that holds [file], or `null` for a root file.
String? firstFolderOf(WorkdirFile file) {
  final slash = file.filename.indexOf('/');
  return slash == -1 ? null : file.filename.substring(0, slash);
}

/// The directory of [file] below the first-level [folder] that holds it, or
/// `null` for a file directly in [folder]. [file] must lie under [folder].
String? directoryWithin(WorkdirFile file, String folder) {
  assert(
    file.filename.startsWith('$folder/'),
    'directoryWithin takes a file under the folder',
  );
  final directory = file.directory;
  return directory == folder ? null : directory?.substring(folder.length + 1);
}

/// Whether the first-level [folder] starts collapsed: a tooling directory
/// is rarely what a reader opens the workspace for.
bool startsCollapsed(String folder) => _toolingDirectories.contains(folder);

/// Whether the first-level [folder] is open: as the reader last set it in
/// [toggles], or else unless it [startsCollapsed].
bool isFolderExpanded(Map<String, bool> toggles, String folder) =>
    toggles[folder] ?? !startsCollapsed(folder);

/// Whether any segment of [path] is a tooling directory's name, at any
/// depth: so a file inside one, or a file with that name, such as the `.git`
/// file a Git worktree writes.
bool isToolingPath(String path) =>
    path.split('/').any(_toolingDirectories.contains);
