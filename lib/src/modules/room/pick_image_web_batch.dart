import 'package:file_picker/file_picker.dart';

import 'pick_file.dart' show PickFileItemError;
import 'pick_image.dart';

/// Reads a web pick's bytes, then revokes its object URLs.
///
/// The body of the web [pickImages], kept free of `package:web` so the VM
/// tests can run it: the web file passes `URL.revokeObjectURL` as
/// [revokeObjectUrl].
///
/// For every picked file the plugin mints an object URL on the file itself and
/// never revokes it, which would keep each picked file reachable for the life
/// of the page. Revoking the URL releases that reference; the bytes read are
/// unaffected. The plugin reads each file's bytes at pick time, and a read
/// here goes through the URL only when it did not — the preload failed, or
/// the file is over the plugin's 2 GB preload limit — so the URLs are revoked
/// once every read is done, and for the whole batch, so that nothing going
/// wrong with one file can strand another file's URL.
///
/// A file the browser refuses to read lands in the result's errors; the rest
/// of the batch is still read.
Future<PickImagesResult> readWebImageBatch(
  List<PlatformFile> picked, {
  required void Function(String url) revokeObjectUrl,
}) async {
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
      if (file.uri.isScheme('blob')) revokeObjectUrl(file.uri.toString());
    }
  }
  return (images: images, errors: errors);
}
