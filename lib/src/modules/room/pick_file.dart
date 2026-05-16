import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mime/mime.dart';

import 'open_file_stream.dart'
    if (dart.library.html) 'open_file_stream_web.dart';

/// A file selected by the user, with metadata and a re-callable stream
/// factory over its contents.
///
/// [openStream] returns a fresh `Stream<List<int>>` on every call so the
/// upload pipeline can re-stream on a retry without re-prompting the
/// user. On native platforms the stream reads chunks lazily from disk;
/// on web the stream re-iterates a held `Uint8List`.
class PickedFile {
  const PickedFile({
    required this.name,
    required this.mimeType,
    required this.size,
    required this.openStream,
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
}

/// Base for failures raised from [pickFile].
///
/// Callers surface a user-facing row via the upload tracker; the
/// wrapped [cause] is preserved for logging and diagnostics.
sealed class PickFileException implements Exception {
  const PickFileException({required this.cause});

  /// The underlying error that triggered the pick failure.
  final Object cause;
}

/// Thrown when the platform file picker itself fails — plugin not
/// wired for the current platform, OS-level picker error, or an
/// invariant violation where the picker returned neither bytes nor a
/// usable path.
class PickFilePickerException extends PickFileException {
  const PickFilePickerException({this.filename, required super.cause});

  /// Filename, when the failure happened after the picker identified a
  /// file (e.g., the bytes-nor-path invariant). `null` when the picker
  /// itself threw before returning any file.
  final String? filename;

  @override
  String toString() => filename == null
      ? 'File picker failed: $cause'
      : 'File picker failed for $filename: $cause';
}

/// User-facing message for a [PickFilePickerException].
///
/// `RangeError` is the canonical signal that the browser ran out of
/// heap allocating the file's bytes — `withData: true` on web reads the
/// whole file into a `Uint8List`. DOM-level `QuotaExceededError` crosses
/// the JS-interop boundary as a generic JS error and still falls
/// through to the catch-all message; that's an accepted limitation.
String pickerErrorMessage(PickFilePickerException error) {
  if (error.cause is RangeError) {
    return 'Selection is too large to load in the browser.';
  }
  return 'Could not open file picker';
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

/// Opens the platform file picker.
///
/// Returns `null` when the user cancels. Throws [PickFilePickerException]
/// when the picker plugin itself fails. Per-file read failures surface
/// later, inside the upload pipeline, when [PickedFile.openStream] is
/// drained.
///
/// Platform-conditional flags:
/// - **Web**: `withData: true` (the file_picker default on web). The
///   stream factory wraps the eagerly-loaded `Uint8List`.
/// - **macOS**: neither flag is supported per file_picker docs; the
///   picker returns a path which we stream from via `dart:io`.
/// - **Other native** (iOS / Android / Windows / Linux): both flags
///   `false` — file_picker still copies to app cache on mobile and
///   populates `path` without setting up unused platform-channel
///   stream infrastructure.
Future<PickedFile?> pickFile() async {
  final FilePickerResult? result;
  try {
    if (kIsWeb) {
      // The static `FilePicker.pickFiles` defaults `withData` to false —
      // despite the file_picker docs claiming it defaults to `true` on
      // web (that's the web impl's signature default, which gets
      // overridden when the static caller passes an explicit value).
      // On web we have no path, so we MUST pass `withData: true` to get
      // bytes back; otherwise `file.bytes` is always null.
      result = await FilePicker.pickFiles(withData: true);
    } else {
      result = await FilePicker.pickFiles(
        withData: false,
        withReadStream: false,
      );
    }
  } on Object catch (error) {
    throw PickFilePickerException(cause: error);
  }
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.first;

  final mimeType = lookupMimeType(file.name) ?? 'application/octet-stream';

  if (kIsWeb) {
    final bytes = file.bytes;
    if (bytes == null) {
      // file_picker's web path uses FileReader.readAsArrayBuffer, which
      // silently yields null on browser heap exhaustion. Surface this
      // as a RangeError so [pickerErrorMessage] maps it to the
      // size-limit message instead of the generic picker-plugin one.
      throw PickFilePickerException(
        filename: file.name,
        cause: RangeError(
          'FileReader returned no bytes for ${file.name} on web '
          '(likely too large for browser heap)',
        ),
      );
    }
    return PickedFile(
      name: file.name,
      mimeType: mimeType,
      size: bytes.length,
      openStream: () => Stream<List<int>>.value(bytes),
    );
  }

  final path = file.path;
  if (path == null) {
    throw PickFilePickerException(
      filename: file.name,
      cause: StateError('picker returned no path for ${file.name}'),
    );
  }
  return PickedFile(
    name: file.name,
    mimeType: mimeType,
    size: file.size,
    openStream: () => openFileStream(path),
  );
}
