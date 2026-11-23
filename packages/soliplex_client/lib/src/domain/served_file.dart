/// A file a server lists and serves for download: an upload or a file in a
/// thread's workspace.
///
/// Implementers must have value equality, so a file can key a map of its
/// state.
abstract interface class ServedFile {
  /// The file's name as the server lists it, a path for a workspace file.
  String get filename;

  /// The last segment of [filename].
  String get basename;

  /// The directories above the file, or `null` when it has none.
  String? get directory;

  /// The file's size in bytes, or `null` when the server did not report a
  /// usable value.
  int? get sizeBytes;
}
