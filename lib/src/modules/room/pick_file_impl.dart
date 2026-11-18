import 'dart:io' show Directory, File, FileSystemException;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:mime/mime.dart';
import 'package:soliplex_folder_picker/soliplex_folder_picker.dart';

import 'open_file_stream.dart';
import 'pick_file.dart';

/// Native implementation of [pickFiles].
///
/// Every native platform hands back a path rather than bytes, which we stream
/// from through `dart:io`. On desktop it is the user's own file; Android and
/// iOS first copy the whole file into app storage, at pick time, so a large
/// pick takes as long to return as that copy. An empty pick is a cancel.
///
/// The size comes from the pick result where the platform reports it, and from
/// the file otherwise. A file whose size cannot be found is reported, with the
/// file system's reason, rather than uploaded, since the upload's
/// `Content-Length` needs it.
Future<PickFilesResult?> pickFilesImpl() async {
  final List<PlatformFile> picked;
  try {
    picked = await FilePicker.pickFiles();
  } on Object catch (error) {
    throw PickFilePickerException(cause: error);
  }
  if (picked.isEmpty) return null;

  final files = <PickedFile>[];
  final errors = <PickFileItemError>[];
  for (final file in picked) {
    final mimeType = lookupMimeType(file.name) ?? 'application/octet-stream';
    final path = file.path;
    if (path == null) {
      errors.add(
        PickFileItemError(
          filename: file.name,
          cause: StateError('picker returned no path for ${file.name}'),
        ),
      );
      continue;
    }
    // From the file itself when the pick result does not carry it, which is
    // every pick on Windows and Linux: the plugin's own `length()` swallows
    // the error that says why the size could not be read.
    final int size;
    try {
      size = file.lengthSync() ?? await File(path).length();
    } on FileSystemException catch (error) {
      errors.add(PickFileItemError(filename: file.name, cause: error));
      continue;
    }
    files.add(
      PickedFile(
        name: file.name,
        mimeType: mimeType,
        size: size,
        openStream: () => openFileStream(path),
      ),
    );
  }
  return (files: files, errors: errors);
}

/// The document-based folder picker, used where [SoliplexFolderPicker.isSupported]
/// says a picked folder's path cannot be read. Replaced in tests.
@visibleForTesting
SoliplexFolderPicker folderPicker = SoliplexFolderPicker();

/// Native implementation of [pickFolder].
///
/// Android picks and reads the folder through [folderPicker]: the path
/// `FilePicker.getDirectoryPath` resolves there lists empty, since scoped
/// storage hides other apps' files under it. Everywhere else the folder comes
/// from [FilePicker.getDirectoryPath] and is walked with
/// `Directory.list(recursive: true, followLinks: false)`.
///
/// Either way, files with any path segment starting with `.` are skipped —
/// this catches dotfiles (`.DS_Store`) and dotdirs (`.git/`). Surviving files
/// have their names mangled via [mangleRelativePath] with the picked folder's
/// name as root. A folder left with nothing to upload is reported as a
/// [NoFilesInFolderError] under the folder's name.
Future<PickFilesResult?> pickFolderImpl() async {
  final picker = folderPicker;
  if (picker.isSupported) return _pickFolderByDocument(picker);

  final String? picked;
  try {
    picked = await FilePicker.getDirectoryPath();
  } on Object catch (error) {
    throw PickFilePickerException(cause: error);
  }
  if (picked == null) return null;

  final base = picked.replaceAll(RegExp(r'[/\\]+$'), '');
  final rootName = base.split(RegExp(r'[/\\]')).last;

  final found = <_FolderFile>[];
  try {
    await for (final entity
        in Directory(base).list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      found.add(
        _FolderFile(
          relativePath: entity.path.substring(base.length + 1),
          size: entity.lengthSync,
          openStream: () => openFileStream(entity.path),
        ),
      );
    }
  } on Object catch (error) {
    throw PickFilePickerException(cause: error);
  }
  return _folderBatch(rootName, found);
}

Future<PickFilesResult?> _pickFolderByDocument(
  SoliplexFolderPicker picker,
) async {
  final PickedFolder? picked;
  try {
    picked = await picker.pick();
  } on Object catch (error) {
    throw PickFilePickerException(cause: error);
  }
  if (picked == null) return null;
  return _folderBatch(picked.name, [
    for (final entry in picked.files)
      _FolderFile(
        relativePath: entry.relativePath,
        size: () =>
            entry.size ??
            (throw StateError('no size reported for ${entry.relativePath}')),
        openStream: () => picker.openRead(entry.uri),
      ),
  ]);
}

/// A file found under a picked folder, before filtering and naming.
class _FolderFile {
  const _FolderFile({
    required this.relativePath,
    required this.size,
    required this.openStream,
  });

  final String relativePath;
  final int Function() size;
  final Stream<List<int>> Function() openStream;
}

PickFilesResult _folderBatch(String rootName, List<_FolderFile> found) {
  final files = <PickedFile>[];
  final errors = <PickFileItemError>[];
  for (final file in found) {
    final relative = file.relativePath;
    final segments = relative.split(RegExp(r'[/\\]'));
    if (segments.any((s) => s.startsWith('.'))) continue;
    try {
      final mangledName = mangleRelativePath(rootName, relative);
      files.add(
        PickedFile(
          name: mangledName,
          mimeType: lookupMimeType(mangledName) ?? 'application/octet-stream',
          size: file.size(),
          openStream: file.openStream,
        ),
      );
    } on Object catch (e) {
      // A path the mangler refuses, or a size that cannot be read.
      errors.add(PickFileItemError(filename: relative, cause: e));
    }
  }
  if (files.isEmpty && errors.isEmpty) {
    errors.add(
      PickFileItemError(
          filename: rootName, cause: const NoFilesInFolderError()),
    );
  }
  return (files: files, errors: errors);
}
