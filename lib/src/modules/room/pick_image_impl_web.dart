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
/// It does cost one thing that has to be undone. For every file it read bytes
/// from — before any of it is validated — the plugin copies those bytes into a
/// `Blob` and mints an object URL it never revokes, which would hold that copy
/// for the life of the page in proportion to what the user picked rather than to
/// what the message keeps. Revoking the URL releases the copy; the bytes we were
/// handed are unaffected.
///
/// `readSequential` is what holds the pick in the order the user made it. The
/// plugin otherwise starts a `FileReader` per file at once and appends each one
/// as it finishes, so a large image chosen first can land behind a small one
/// chosen second — and the order images sit in is the whole point of carrying
/// them inline.
///
/// The plugin ignores `compressionQuality`, so nothing is re-encoded here.
Future<PickImagesResult?> pickImagesImpl() async {
  final FilePickerResult? result;
  try {
    result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
      readSequential: true,
    );
  } on Object catch (error) {
    throw PickFilePickerException(cause: error);
  }
  if (result == null) return null;

  // Discharged for the whole batch before a byte of it is looked at, so that
  // nothing going wrong with one file can strand another file's copy.
  for (final file in result.files) {
    // The plugin puts the object URL it minted where a native path would go.
    final blobUrl = file.path;
    if (blobUrl != null && blobUrl.startsWith('blob:')) {
      web.URL.revokeObjectURL(blobUrl);
    }
  }

  final images = <PickedImage>[];
  final errors = <PickFileItemError>[];
  for (final file in result.files) {
    final bytes = file.bytes;
    if (bytes == null) {
      errors.add(
        PickFileItemError(
          filename: file.name,
          cause: StateError('browser returned no bytes for ${file.name}'),
        ),
      );
      continue;
    }
    images.add(PickedImage.fromBytes(name: file.name, bytes: bytes));
  }
  return (images: images, errors: errors);
}
