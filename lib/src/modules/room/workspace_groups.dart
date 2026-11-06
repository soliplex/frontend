import 'package:flutter/foundation.dart' show immutable;
import 'package:soliplex_client/soliplex_client.dart' show WorkdirFile;

import 'file_sort.dart';

/// A folder of a workspace listing, and everything below it.
///
/// A folder whose only content is one folder merges with it into one: `raw/archive/2023` rather than three folders opened in turn.
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
/// gives, rooted at the workspace root. At every level, files and folders go
/// by name.
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
      folder.folders.length == 1) {
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
  return WorkspaceFolder(
    path: chainPath,
    name: chainName,
    files: flatWorkspace(folder.files, sort),
    // By the first folder of a merged chain: the one beside its siblings.
    folders: sortFiles(
      children,
      sort,
      path: (f) => f.name.split('/').first,
      modifiedAt: (_) => null,
      sizeBytes: (_) => null,
    ),
  );
}

/// Every file, by [sortFiles].
List<WorkdirFile> flatWorkspace(List<WorkdirFile> listing, FileSort sort) =>
    sortFiles(
      listing,
      sort,
      path: (f) => f.filename,
      modifiedAt: (f) => f.modifiedAt,
      sizeBytes: (f) => f.sizeBytes,
    );

/// The folders that hold [file], outermost first: `a`, `a/b` for `a/b/c.txt`.
List<String> ancestorsOf(WorkdirFile file) {
  final segments = file.filename.split('/');
  return [
    for (var i = 1; i < segments.length; i++) segments.take(i).join('/'),
  ];
}

String _lastSegment(String path) => path.substring(path.lastIndexOf('/') + 1);

/// Whether the folder at [path] is open: as the reader last set it in
/// [toggles]; where they have not, open only when it is [topLevel].
bool isFolderExpanded(
  Map<String, bool> toggles,
  String path, {
  required bool topLevel,
}) =>
    toggles[path] ?? topLevel;

/// The paths of every folder in [root]'s tree that is open, by [toggles] or
/// by default, at any depth. That includes folders inside a closed one,
/// hidden now, which show open again when it reopens.
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
