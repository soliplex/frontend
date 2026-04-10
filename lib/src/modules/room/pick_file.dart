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

/// Opens the platform file picker and returns the selected file with
/// bytes loaded, or null if the user cancelled or the file couldn't
/// be read.
Future<PickedFile?> pickFile() async {
  final result = await FilePicker.pickFiles(withData: true);
  if (result == null || result.files.isEmpty) return null;
  final file = result.files.first;
  if (file.bytes == null && file.path == null) return null;

  final bytes = file.bytes ?? await readFileBytes(file.path!);
  if (bytes == null) return null;

  final mimeType = lookupMimeType(file.name) ?? 'application/octet-stream';
  return PickedFile(name: file.name, bytes: bytes, mimeType: mimeType);
}
