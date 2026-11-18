import 'package:flutter/services.dart' show PlatformException;

import 'pick_file_impl.dart'
    if (dart.library.js_interop) 'pick_file_impl_web.dart';

/// A file selected by the user, with metadata and a re-callable stream
/// factory over its contents.
///
/// [openStream] returns a fresh `Stream<List<int>>` on every call so the
/// upload pipeline can re-stream on a retry without re-prompting the
/// user. On native platforms the stream reads chunks lazily from disk;
/// on web it adapts a fresh `ReadableStream` from `Blob.stream()`.
class PickedFile {
  const PickedFile({
    required this.name,
    required this.mimeType,
    required this.size,
    required this.openStream,
    this.webFileBlob,
  });

  /// Display name (basename). Not used as a filesystem path.
  final String name;

  /// MIME type derived from the filename extension, falling back to
  /// `application/octet-stream` when unknown.
  final String mimeType;

  /// File length in bytes. Used to set the request's `Content-Length`.
  final int size;

  /// Re-callable stream factory over the file's bytes.
  final Stream<List<int>> Function() openStream;

  /// Opaque reference to a browser File/Blob (typed as `Object` so this
  /// file stays free of `package:web` imports). Set on web; `null` on
  /// native. When present, the upload pipeline can route through
  /// `WebMultipartFileBody` so the browser handles multipart encoding
  /// and streams from the file's disk-backed storage — avoiding any
  /// JS-heap buffering of the file's bytes.
  final Object? webFileBlob;
}

/// Successful batch from [pickFiles]: zero or more usable files plus
/// zero or more per-file failures the caller should surface as Failed
/// rows.
typedef PickFilesResult = ({
  List<PickedFile> files,
  List<PickFileItemError> errors,
});

/// Per-file failure inside a [pickFiles] batch. Siblings keep flowing;
/// the caller routes each entry to the upload tracker's
/// `recordClientError` so the user sees a Failed row per affected file.
class PickFileItemError {
  const PickFileItemError({required this.filename, required this.cause});

  final String filename;
  final Object cause;
}

/// Base for failures raised from [pickFiles].
sealed class PickFileException implements Exception {
  const PickFileException({required this.cause});

  /// The underlying error that triggered the pick failure.
  final Object cause;
}

/// Thrown when the platform file picker itself fails — plugin not
/// wired for the current platform or OS-level picker error.
///
/// Per-file failures (e.g., one file in a multi-pick has unreadable
/// bytes) do NOT throw; they appear in [PickFilesResult.errors].
class PickFilePickerException extends PickFileException {
  const PickFilePickerException({required super.cause});

  @override
  String toString() => 'File picker failed: $cause';
}

/// The cause [pickFolder] reports, under the folder's name, for a folder with
/// nothing to upload once dotfiles are skipped. Reported rather than read as a
/// cancel, so a folder the app was not let into does not look like nothing
/// happened.
class NoFilesInFolderError implements Exception {
  const NoFilesInFolderError();

  @override
  String toString() => 'The folder has no files to upload';
}

/// User-facing message for a failure of the pick itself, the cause of a
/// [PickFilePickerException].
///
/// Some of these happen after the picker closed: Android's `unknown_path`, for
/// a pick it could not copy, and iOS's `load_failed`, when none of the picked
/// photos could load (iCloud-only photos while offline, for one). They are
/// worded as files that could not be loaded, not as a picker that would not
/// open.
///
/// `RangeError` is the canonical signal that the browser ran out of
/// heap allocating a file's bytes — historically surfaced by the
/// buffered web picker. DOM-level `QuotaExceededError` crosses the
/// JS-interop boundary as a generic JS error and still falls through
/// to the catch-all message; that's an accepted limitation.
String pickerErrorMessage(Object cause) {
  if (cause is PlatformException) {
    switch (cause.code) {
      case 'load_failed':
        return 'Could not load the picked files. '
            'If they are in iCloud, check your connection.';
      case 'unknown_path':
        return 'Could not load the picked files.';
    }
  }
  if (cause is RangeError) {
    return 'Selection is too large to load in the browser.';
  }
  return 'Could not open file picker';
}

/// User-facing message for one file of a pick that failed, the cause of a
/// [PickFileItemError]: the picker opened and closed, so the problem is the
/// file.
String pickedFileErrorMessage(Object cause) {
  if (cause is NoFilesInFolderError) {
    return 'No files to upload in this folder.';
  }
  if (cause is RangeError) {
    return 'Selection is too large to load in the browser.';
  }
  return 'Could not read this file.';
}

/// Flattens a folder-relative path into a single safe filename, joining
/// segments with `__` and prepending the picked folder's basename.
///
/// Example: picked folder `myproject` containing `src/main.dart` →
/// `myproject__src__main.dart`.
///
/// Used for folder uploads where the backend stores files in a flat
/// directory and applies `pathlib.Path(filename).name` — this mangler
/// produces flat names with no path separators, so the backend's
/// basename strip is a no-op.
///
/// Throws [FormatException] for path-traversal segments (`..`, `.`) or
/// an empty `rootName`. The picker layer should route these to the
/// upload tracker's `recordClientError` so the user sees a Failed row.
///
/// **Collision caveat:** if a source filename already contains `__`,
/// two distinct paths can mangle to the same string — e.g.
/// `a__b/c.txt` and `a/b__c.txt` both yield `a__b__c.txt`. Accepted
/// edge case; the picker doesn't deduplicate.
String mangleRelativePath(String rootName, String relativePath) {
  if (rootName.isEmpty) {
    throw const FormatException(
      'mangleRelativePath requires a non-empty rootName',
    );
  }
  final segments =
      relativePath.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) {
    throw FormatException(
      'mangleRelativePath requires at least one path segment',
      relativePath,
    );
  }
  for (final seg in segments) {
    if (seg == '..' || seg == '.') {
      throw FormatException(
        'Path traversal segment ("$seg") in folder upload',
        relativePath,
      );
    }
  }
  return [rootName, ...segments].join('__');
}

/// Opens the platform file picker with multi-select enabled.
///
/// Returns `null` when the user cancels. Throws [PickFilePickerException]
/// when the picker plugin itself fails. Per-file failures this side sees
/// do NOT abort the batch — they appear in [PickFilesResult.errors] so the
/// caller can route each one to the upload tracker's `recordClientError`.
/// On Android and iOS an item the plugin could not copy is dropped from a
/// pick that kept at least one other before it reaches this side, with no
/// error to report.
Future<PickFilesResult?> pickFiles() => pickFilesImpl();

/// Opens the platform directory picker and walks the chosen folder for
/// uploadable files.
///
/// Returns `null` when the user cancels. Dotfiles and entries under
/// dot-prefixed directories are skipped; a native pick left with no files
/// answers a single [NoFilesInFolderError] in [PickFilesResult.errors]. On web
/// a folder with no files never reaches the app: the browser reads it as a
/// cancel.
///
/// A failure of the directory picker itself reads as a cancel too on Android,
/// iOS and macOS, where the plugin catches it and answers null, and on Linux,
/// where a failed portal request answers null. On Windows it throws
/// [PickFilePickerException].
///
/// Each returned [PickedFile] has its name mangled via
/// [mangleRelativePath] using the picked folder's basename as the root,
/// so the backend's flat storage and `pathlib.Path(filename).name`
/// stripping leave the names intact.
Future<PickFilesResult?> pickFolder() => pickFolderImpl();
