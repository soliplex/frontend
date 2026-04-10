import 'dart:io';

/// Reads file bytes from a path (native platforms where file_picker
/// provides a path instead of bytes).
Future<List<int>?> readFileBytes(String path) async {
  try {
    return await File(path).readAsBytes();
  } on Object {
    return null;
  }
}
