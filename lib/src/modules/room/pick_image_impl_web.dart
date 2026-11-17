import 'package:file_picker/file_picker.dart';
import 'package:web/web.dart' as web;

import 'pick_file.dart' show PickFilePickerException, pickFiles;
import 'pick_image.dart';
import 'pick_image_web_batch.dart';

/// Web implementation of [pickImages].
///
/// Uses `file_picker` where [pickFiles] hand-rolls an `<input>`. That bypass
/// exists so an upload can re-stream a large file from its blob instead of
/// buffering it, which an inline image cannot use: it is held whole for as long
/// as it sits in the composer, and drawn from those bytes. So the requirement
/// the bypass serves is absent here, and asking `file_picker` for the bytes
/// costs no interop of our own.
///
/// It does cost one thing that has to be undone: the object URL the plugin
/// mints on every picked file. [readWebImageBatch] reads the bytes, then
/// revokes the URLs.
///
/// The plugin returns the files in the browser's `FileList` order, which the
/// browser chooses, not necessarily the order the user picked them in.
///
/// The plugin ignores `compressionQuality`, so nothing is re-encoded here.
Future<PickImagesResult?> pickImagesImpl() async {
  final List<PlatformFile> picked;
  try {
    picked = await FilePicker.pickFiles(type: FileType.image);
  } on Object catch (error) {
    throw PickFilePickerException(cause: error);
  }
  if (picked.isEmpty) return null;

  return readWebImageBatch(
    picked,
    // A lambda: the web compilers refuse a tear-off of an interop member.
    revokeObjectUrl: (url) => web.URL.revokeObjectURL(url),
  );
}
