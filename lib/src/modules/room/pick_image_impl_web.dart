import 'package:file_picker/file_picker.dart';
import 'package:web/web.dart' as web;

import 'pick_file.dart';
import 'pick_image.dart';

/// Web implementation of [pickImages].
///
/// Uses `file_picker` where [pickFiles] hand-rolls an `<input>`. That bypass
/// exists so an upload can re-stream a large file from its blob instead of
/// buffering it, which an inline image cannot use: it is held whole for as long
/// as it sits in the composer, and drawn from those bytes. So the requirement
/// the bypass serves is absent here, and asking `file_picker` for the bytes
/// costs no interop of our own.
///
/// It does cost one thing that has to be undone. For every picked file the
/// plugin mints an object URL on the file itself and never revokes it, which
/// would keep each picked file reachable for the life of the page. Revoking the
/// URL releases that reference; the bytes we read are unaffected. The URLs are
/// revoked only once every read is done, because a read goes through them, and
/// for the whole batch, so that nothing going wrong with one file can strand
/// another file's URL.
///
/// The plugin returns the files in the order the user picked them, which is
/// the whole point of carrying images inline.
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

  final images = <PickedImage>[];
  final errors = <PickFileItemError>[];
  try {
    for (final file in picked) {
      try {
        images.add(
          PickedImage.fromBytes(
            name: file.name,
            bytes: await file.readAsBytes(),
          ),
        );
      } on Object catch (error) {
        // The browser refusing to read a picked file is that file's problem.
        errors.add(PickFileItemError(filename: file.name, cause: error));
      }
    }
  } finally {
    for (final file in picked) {
      if (file.uri.isScheme('blob')) {
        web.URL.revokeObjectURL(file.uri.toString());
      }
    }
  }
  return (images: images, errors: errors);
}
