import 'dart:developer' as dev;

/// Stub for web — file_picker always provides bytes on web, so this
/// entrypoint is never called at runtime. If it ever is, that's a
/// coding bug worth flagging loudly; the thrown [UnsupportedError]
/// propagates to the caller as a typed pick failure.
Future<List<int>> readFileBytes(String path) async {
  dev.log(
    'readFileBytes called on web; file_picker should have provided bytes',
    name: 'pick_file',
    level: 1000,
  );
  throw UnsupportedError('readFileBytes is not used on the web platform');
}
