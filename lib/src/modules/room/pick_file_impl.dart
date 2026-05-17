import 'dart:io' show Directory, File;

import 'package:file_picker/file_picker.dart';
// ignore: implementation_imports
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:mime/mime.dart';

import 'open_file_stream.dart';
import 'pick_file.dart';

/// Native implementation of [pickFiles].
///
/// Uses `file_picker` with platform-conditional flags:
/// - **macOS**: neither `withData` nor `withReadStream` is supported per
///   file_picker docs; the picker returns paths which we stream from
///   via `dart:io`.
/// - **iOS / Android / Windows / Linux**: both flags `false` —
///   file_picker still copies to app cache on mobile and populates
///   `path` without setting up unused platform-channel stream
///   infrastructure.
Future<PickFilesResult?> pickFilesImpl() async {
  final FilePickerResult? result;
  try {
    result = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: false,
      withReadStream: false,
    );
  } on Object catch (error) {
    throw PickFilePickerException(cause: error);
  }
  if (result == null || result.files.isEmpty) return null;

  final files = <PickedFile>[];
  final errors = <PickFileItemError>[];
  for (final file in result.files) {
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
    files.add(
      PickedFile(
        name: file.name,
        mimeType: mimeType,
        size: file.size,
        openStream: () => openFileStream(path),
      ),
    );
  }
  return (files: files, errors: errors);
}

/// Native implementation of [pickFolder].
///
/// Uses `FilePicker.getDirectoryPath` then walks the chosen directory
/// via `Directory.list(recursive: true, followLinks: false)`. Files
/// whose any path segment starts with `.` are skipped — this catches
/// dotfiles (`.DS_Store`) and dotdirs (`.git/`). Surviving files have
/// their names mangled via [mangleRelativePath] with the picked
/// folder's basename as root.
Future<PickFilesResult?> pickFolderImpl() async {
  final String? picked;
  try {
    picked = await FilePickerPlatform.instance.getDirectoryPath();
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
