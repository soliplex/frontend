import 'dart:io';

/// Opens a re-readable byte stream for a file at [path] (native
/// platforms). Each invocation returns a fresh `Stream<List<int>>`, so
/// callers can re-stream the same file on a retry without re-picking.
///
/// `dart:io`'s [File.openRead] reads chunks lazily — typical chunk size
/// is 64 KB — so the file's bytes never fully materialize in RAM.
Stream<List<int>> openFileStream(String path) {
  return File(path).openRead();
}
