import 'dart:io' show File, IOException;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:soliplex_logging/soliplex_logging.dart';

import 'pick_file.dart';
import 'pick_image.dart';

final _logger = LogManager.instance.getLogger('soliplex_frontend.pick_image');

/// Native implementation of [pickImages].
///
/// `type: FileType.image` is what narrows the chooser to images, and it is why
/// `compressionQuality` matters here — see [inlineImageCompressionQuality]. On
/// iOS it opens the photo library; Android resolves it through the system
/// chooser, which usually offers the files app alongside photos.
///
/// Bytes come from the returned path everywhere rather than through `withData`.
/// Both mobile platforms leave behind a copy that has to be deleted once its
/// bytes are held — see [_discardPickerCopy] — so the path is needed on those
/// regardless, and reading it directly keeps one path for every native
/// platform. Every native platform populates it; the `path == null` branch
/// below is belt and braces, since the plugin's own type allows it.
///
/// Selection order does not survive iOS, where the web implementation's
/// `readSequential` has no counterpart. The plugin starts a load for every
/// picked asset and appends to its result from inside each completion handler,
/// so a large photo picked first can land behind a small one picked second.
/// The paths it hands back are minted names carrying a UUID and a timestamp,
/// with nothing of the order in them, so this cannot put them back.
Future<PickImagesResult?> pickImagesImpl() async {
  final FilePickerResult? result;
  try {
    result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: false,
      withReadStream: false,
      compressionQuality: inlineImageCompressionQuality(
        isIOS: defaultTargetPlatform == TargetPlatform.iOS,
      ),
    );
  } on Object catch (error) {
    throw PickFilePickerException(cause: error);
  }
  if (result == null) return null;

  final images = <PickedImage>[];
  final errors = <PickFileItemError>[];
  for (final file in result.files) {
    final path = file.path;
    if (path == null) {
      errors.add(
        PickFileItemError(
          filename: file.name,
          cause: StateError('picker returned no path for ${file.name}'),
        ),
      );
      continue;
    }
    try {
      images.add(
        PickedImage.fromBytes(
          name: file.name,
          bytes: await File(path).readAsBytes(),
        ),
      );
    } on IOException catch (error) {
      // Only the file's own problems are the file's to report. Anything else
      // is ours, and reporting it as the user's image being unreadable would
      // hide it behind a message they can do nothing with.
      errors.add(PickFileItemError(filename: file.name, cause: error));
    } finally {
      // Also on the failing path. The read most likely to fail is of the
      // largest image, which is the copy worth least leaving behind.
      await _discardPickerCopy(path);
    }
  }
  return (images: images, errors: errors);
}

/// Deletes the copy the picker made of an image, now that its bytes are held.
///
/// Only where the path *is* a copy. Both mobile platforms write the pick into
/// app storage, while on desktop the path is the user's own file and deleting
/// it would destroy their picture.
///
/// The stakes differ by platform. Android's copy goes to the cache directory,
/// which the OS reclaims under pressure and which the shell's boot-time
/// `FilePicker.clearTemporaryFiles()` sweeps; deleting here just keeps a long
/// session from accumulating copies it is already done with. iOS writes to the
/// Documents directory, which nothing reclaims — not the system, and not that
/// boot-time sweep, which only covers the temporary directory — and which a
/// backup carries. There, an undeleted copy costs its size for the life of the
/// install.
///
/// Best effort: the bytes are already in hand, so failing to tidy up costs
/// nothing this call needs. It is logged all the same, because on iOS a delete
/// that always failed would grow the install forever with nothing to show for
/// it.
Future<void> _discardPickerCopy(String path) async {
  if (defaultTargetPlatform != TargetPlatform.iOS &&
      defaultTargetPlatform != TargetPlatform.android) {
    return;
  }
  try {
    await File(path).delete();
  } on Object catch (error, stackTrace) {
    _logger.warning(
      'could not discard the picker copy of an image',
      error: error,
      stackTrace: stackTrace,
      attributes: {'platform': defaultTargetPlatform.name},
    );
  }
}
