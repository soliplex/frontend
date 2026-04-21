import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';

import 'read_file_bytes.dart' if (dart.library.html) 'read_file_bytes_web.dart';

/// A file selected by the user, with bytes loaded and MIME type resolved.
class PickedFile {
  const PickedFile({
    required this.name,
    required this.bytes,
    required this.mimeType,
  });

  final String name;
  final List<int> bytes;
  final String mimeType;
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

/// Thrown when the user picked a file but its bytes could not be read
/// from disk.
class PickFileReadException extends PickFileException {
  const PickFileReadException({required this.filename, required super.cause});

  final String filename;

  @override
  String toString() => 'Failed to read $filename: $cause';
}

/// Opens the platform file picker.
///
/// Returns `null` when the user cancels. Throws a [PickFileException]
/// subtype on any failure so callers can surface inline feedback
/// instead of silently no-op-ing.
Future<PickedFile?> pickFile() async {
  final FilePickerResult? result;
  try {
    result = await FilePicker.pickFiles(withData: true);
  } on Object catch (error) {
    throw PickFilePickerException(cause: error);
  }
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.first;
  if (file.bytes == null && file.path == null) {
    throw PickFilePickerException(
      filename: file.name,
      cause: StateError('picker returned no bytes or path for ${file.name}'),
    );
  }

  final List<int> bytes;
  if (file.bytes != null) {
    bytes = file.bytes!;
  } else {
    try {
      bytes = await readFileBytes(file.path!);
    } on Object catch (error) {
      throw PickFileReadException(filename: file.name, cause: error);
    }
  }

  final mimeType = lookupMimeType(file.name) ?? 'application/octet-stream';
  return PickedFile(name: file.name, bytes: bytes, mimeType: mimeType);
}
