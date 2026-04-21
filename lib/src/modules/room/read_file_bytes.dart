import 'dart:io';

/// Reads file bytes from a path (native platforms where file_picker
/// provides a path instead of bytes). Propagates I/O errors so the
/// caller can surface them.
Future<List<int>> readFileBytes(String path) async {
  return File(path).readAsBytes();
}
