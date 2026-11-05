import 'package:flutter/foundation.dart' show immutable;
import 'package:soliplex_client/soliplex_client.dart' show WorkdirFile;

import 'file_sort.dart';

/// Directories that tools, not the agent's task, fill: Git's repository and
/// CPython's bytecode cache. The names are fixed by those tools.
const _toolingDirectories = {'.git', '__pycache__'};

/// A folder of a workspace listing, and everything below it.
///
/// A folder whose only content is one non-tooling folder merges with it into
/// one: `raw/archive/2023` rather than three folders opened in turn.
@immutable
class WorkspaceFolder {
  const WorkspaceFolder({
    required this.path,
    required this.name,
    required this.files,
    required this.folders,
  });

  /// From the workspace root: `crm_app`, `raw/archive/2023`; empty for the
  /// root. For a merged chain, the path of its last folder.
  final String path;

  /// What the folder's row shows: its path below its parent folder, which
  /// is more than one segment for a merged chain.
  final String name;

  /// The files directly in this folder.
  final List<WorkdirFile> files;

  final List<WorkspaceFolder> folders;

  /// Every file below this folder, at any depth.
  int get fileCount =>
      files.length + folders.fold(0, (count, f) => count + f.fileCount);

  /// When the most recently modified file below this folder, at any depth,
  /// changed; null when none has a time.
  DateTime? get latestChange => [
        ...files.map((f) => f.modifiedAt).nonNulls,
        ...folders.map((f) => f.latestChange).nonNulls,
      ].fold<DateTime?>(
        null,
        (latest, t) => latest == null || t.isAfter(latest) ? t : latest,
      );
}

/// The folder tree of a workspace listing, in the direction [descending]
/// gives, rooted at the workspace root. At every level, files go by name
/// with [isToolingPath] files after the rest; folders go by name, except
/// that tooling folders come last, by name ascending in both directions.
/// They hold no output a reader looks for, so they stay out of the way of
/// the folders that do.
WorkspaceFolder workspaceTree(
  List<WorkdirFile> listing, {
  required bool descending,
}) {
  final root = _FolderDraft();
  for (final file in listing) {
    var folder = root;
    for (final segment in ancestorsOf(file).map(_lastSegment)) {
      folder = folder.folders[segment] ??= _FolderDraft();
    }
    folder.files.add(file);
  }
  return _build(
    root,
    path: '',
    name: '',
    sort: descending ? FileSort.foldersZToA : FileSort.foldersAToZ,
  );
}

class _FolderDraft {
  final files = <WorkdirFile>[];
  final folders = <String, _FolderDraft>{};
}

WorkspaceFolder _build(
  _FolderDraft draft, {
  required String path,
  required String name,
  required FileSort sort,
}) {
  var folder = draft;
  var chainPath = path;
  var chainName = name;
  // The root never merges: its files and folders are the workspace's own.
  while (chainPath.isNotEmpty &&
      folder.files.isEmpty &&
      folder.folders.length == 1 &&
      !_toolingDirectories.contains(folder.folders.keys.single)) {
    final MapEntry(:key, :value) = folder.folders.entries.single;
    chainPath = '$chainPath/$key';
    chainName = '$chainName/$key';
    folder = value;
  }
  final children = [
    for (final MapEntry(:key, :value) in folder.folders.entries)
      _build(
        value,
        path: chainPath.isEmpty ? key : '$chainPath/$key',
        name: key,
        sort: sort,
      ),
  ];
  final files = flatWorkspace(folder.files, sort);
  return WorkspaceFolder(
    path: chainPath,
    name: chainName,
    files: [...files.files, ...files.tooling],
    folders: [
      // By the first folder of a merged chain: the one beside its siblings.
      ...sortFiles(
        children.where((f) => !isToolingPath(f.name)),
        sort,
        path: (f) => f.name.split('/').first,
        modifiedAt: (_) => null,
        sizeBytes: (_) => null,
      ),
      ...children.where((f) => isToolingPath(f.name)).toList()
        ..sort((a, b) => a.name.compareTo(b.name)),
    ],
  );
}

/// Every file, split into the files outside tooling paths and the files
/// inside them ([isToolingPath]), each part by [sortFiles].
({List<WorkdirFile> files, List<WorkdirFile> tooling}) flatWorkspace(
  List<WorkdirFile> listing,
  FileSort sort,
) {
  List<WorkdirFile> sorted(Iterable<WorkdirFile> files) => sortFiles(
        files,
        sort,
        path: (f) => f.filename,
        modifiedAt: (f) => f.modifiedAt,
        sizeBytes: (f) => f.sizeBytes,
      );
  return (
    files: sorted(listing.where((f) => !isToolingPath(f.filename))),
    tooling: sorted(listing.where((f) => isToolingPath(f.filename))),
  );
}

/// The folders that hold [file], outermost first: `a`, `a/b` for `a/b/c.txt`.
List<String> ancestorsOf(WorkdirFile file) {
  final segments = file.filename.split('/');
  return [
    for (var i = 1; i < segments.length; i++) segments.take(i).join('/'),
  ];
}

String _lastSegment(String path) => path.substring(path.lastIndexOf('/') + 1);

/// Whether the folder at [path] is open: as the reader last set it in
/// [toggles], or else open only for a [topLevel] folder that is not tooling
/// output, which is rarely what a reader opens the workspace for.
bool isFolderExpanded(
  Map<String, bool> toggles,
  String path, {
  required bool topLevel,
}) =>
    toggles[path] ?? (topLevel && !isToolingPath(path));

/// The paths of every folder in [root]'s tree that is open, by [toggles] or
/// by default, at any depth: those inside a closed folder too, which show
/// open again when it reopens.
List<String> openFolders(WorkspaceFolder root, Map<String, bool> toggles) {
  final open = <String>[];
  void visit(WorkspaceFolder folder, {required bool topLevel}) {
    if (isFolderExpanded(toggles, folder.path, topLevel: topLevel)) {
      open.add(folder.path);
    }
    for (final child in folder.folders) {
      visit(child, topLevel: false);
    }
  }

  for (final folder in root.folders) {
    visit(folder, topLevel: true);
  }
  return open;
}

/// Whether the reader sees an open folder in [root]'s tree: one is shown
/// only while every folder above it is open, so exactly when a top-level
/// folder is.
bool anyFolderOpen(WorkspaceFolder root, Map<String, bool> toggles) =>
    root.folders.any((f) => isFolderExpanded(toggles, f.path, topLevel: true));

/// Whether any segment of [path] is a tooling directory's name, at any
/// depth: so a file inside one, or a file with that name, such as the `.git`
/// file a Git worktree writes.
bool isToolingPath(String path) =>
    path.split('/').any(_toolingDirectories.contains);
