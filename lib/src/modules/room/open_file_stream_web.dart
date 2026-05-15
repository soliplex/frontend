import 'dart:developer' as dev;

/// Stub for web — `file_picker` on web returns bytes directly, so the
/// path-based stream entrypoint is never called at runtime. If it ever
/// is, that's a coding bug worth flagging loudly; the thrown
/// [UnsupportedError] propagates to the caller as a typed pick failure.
Stream<List<int>> openFileStream(String path) {
  dev.log(
    'openFileStream called on web; file_picker should have provided bytes',
    name: 'pick_file',
    level: 1000,
  );
  throw UnsupportedError('openFileStream is not used on the web platform');
}
