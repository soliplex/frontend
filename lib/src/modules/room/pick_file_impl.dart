import 'dart:io' show Directory, File;

import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';

import 'open_file_stream.dart';
import 'pick_file.dart';

/// Native implementation of [pickFiles].
///
/// `file_picker` reads nothing at pick time: every native platform hands back
/// a path (mobile copies the pick into app storage first), which we stream
/// from through `dart:io`. An empty pick is a cancel.
///
/// The size comes from the pick result where the platform reports it, and from
/// the file otherwise. A file whose size cannot be found is reported rather
/// than uploaded, since the upload's `Content-Length` needs it.
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
    final size = file.lengthSync() ?? await file.length();
    if (size == null) {
      errors.add(
        PickFileItemError(
          filename: file.name,
          cause: StateError('could not read the size of ${file.name}'),
        ),
      );
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

/// Native implementation of [pickFolder].
///
/// Uses [FilePicker.getDirectoryPath] then walks the chosen directory
/// via `Directory.list(recursive: true, followLinks: false)`. Files
/// whose any path segment starts with `.` are skipped — this catches
/// dotfiles (`.DS_Store`) and dotdirs (`.git/`). Surviving files have
/// their names mangled via [mangleRelativePath] with the picked
/// folder's basename as root.
Future<PickFilesResult?> pickFolderImpl() async {
  final String? picked;
  try {
    picked = await FilePicker.getDirectoryPath();
  } on Object catch (error) {
    throw PickFilePickerException(cause: error);
  }
  if (picked == null) return null;

  final base = picked.replaceAll(RegExp(r'[/\\]+$'), '');
  final rootName = base.split(RegExp(r'[/\\]')).last;

  final files = <PickedFile>[];
  final errors = <PickFileItemError>[];
  try {
    await for (final entity
        in Directory(base).list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = entity.path.substring(base.length + 1);
      final segments = relative.split(RegExp(r'[/\\]'));
      if (segments.any((s) => s.startsWith('.'))) continue;
      try {
        final mangledName = mangleRelativePath(rootName, relative);
        final mimeType =
            lookupMimeType(mangledName) ?? 'application/octet-stream';
        files.add(
          PickedFile(
            name: mangledName,
            mimeType: mimeType,
            size: entity.lengthSync(),
            openStream: () => openFileStream(entity.path),
          ),
        );
      } on FormatException catch (e) {
        errors.add(PickFileItemError(filename: relative, cause: e));
      }
    }
  } on Object catch (error) {
    throw PickFilePickerException(cause: error);
  }

  if (files.isEmpty && errors.isEmpty) return null;
  return (files: files, errors: errors);
}
