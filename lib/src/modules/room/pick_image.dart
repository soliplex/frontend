import 'dart:typed_data';

import 'package:mime/mime.dart';

import 'pick_file.dart' show PickFileItemError, PickFilePickerException;
import 'pick_image_impl.dart'
    if (dart.library.js_interop) 'pick_image_impl_web.dart';

/// An image the user picked, with its bytes in hand.
///
/// Held whole where a picked *file* streams: an upload re-reads its source on a
/// retry, while an inline image becomes part of the message the composer is
/// building and is drawn as a thumbnail while it sits there.
class PickedImage {
  /// Creates a picked image of a known type.
  const PickedImage({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  /// Creates a picked image, typing it by what [bytes] hold and falling back to
  /// [name]'s extension.
  ///
  /// Content first because the name can lie, and one way it lies matters here:
  /// iOS is asked to hand back a JPEG in place of an iPhone's HEIC, and a HEIC
  /// delivered under a `.jpeg` name would otherwise be typed as JPEG and sent
  /// to the model as one. Reading the type from the bytes makes that a
  /// rejection the user can see instead.
  ///
  /// It catches the HEIF brands `mime` carries a magic number for — `heic`,
  /// `heix`, `mif1` — and no others. One boxed as `msf1` or `hevc` has nothing
  /// to match against, so it falls through to the extension and is typed by
  /// the name after all.
  factory PickedImage.fromBytes({
    required String name,
    required Uint8List bytes,
  }) =>
      PickedImage(
        name: name,
        mimeType: lookupMimeType(name, headerBytes: bytes) ??
            'application/octet-stream',
        bytes: bytes,
      );

  /// Display name (basename), as the picker reported it. Names the file in
  /// feedback about one that could not be attached — though iOS's photo picker
  /// substitutes a name of its own, so there it identifies the file to us
  /// rather than to the user.
  final String name;

  /// The type of [bytes]: what they hold, or what [name]'s extension claims
  /// when nothing recognises them. `application/octet-stream` when neither
  /// answers, which no allow-list carries — so an image that cannot be typed is
  /// turned away rather than sent as opaque bytes.
  final String mimeType;

  /// The encoded image file bytes, exactly as picked.
  final Uint8List bytes;
}

/// Successful batch from [pickImages]: zero or more images the composer can
/// consider, plus zero or more per-file failures for it to report.
typedef PickImagesResult = ({
  List<PickedImage> images,
  List<PickFileItemError> errors,
});

/// What to pass the picker as `compressionQuality`, which means two unrelated
/// things depending on the platform.
///
/// On iOS the number is read only as a boolean: any non-zero value flips
/// `PHPicker` to Compatible mode, which hands us JPEG in place of the HEIC an
/// iPhone shoots by default — `1` and `100` are identical there. On Android the
/// same number is a real re-encode quality handed to `Bitmap.compress`, so
/// anything above zero silently recompresses every image the user picks, which
/// is the one thing this path exists to avoid. So one value cannot serve both:
/// `90` would destroy Android's originals and `1` would keep iOS's transcode
/// while destroying them anyway.
int inlineImageCompressionQuality({required bool isIOS}) => isIOS ? 100 : 0;

/// Opens the platform image picker with multi-select enabled, and reads the
/// bytes of everything it returns.
///
/// Returns `null` only when the user cancels. Throws [PickFilePickerException]
/// when the picker itself fails. A file this reads nothing usable from does not
/// abort the batch — it lands in [PickImagesResult.errors], so the composer can
/// attach the user's other images and still say which one it could not.
///
/// A batch holding neither images nor errors is a third outcome, and not a
/// cancel: Android answers a pick it could not copy a single item out of with
/// an empty list, having dropped the names on its side. Handing that back as a
/// cancel would leave the user looking at a button that did nothing, so it
/// comes back as the empty batch it is and the composer speaks for it.
///
/// The per-file guarantee stops at what the plugin reports. iOS's photo picker
/// handles a per-item failure by logging it natively and returning the items
/// that did work, so a pick of four photos can arrive as three with nothing to
/// say the fourth existed. Nothing on this side can see the difference.
Future<PickImagesResult?> pickImages() => pickImagesImpl();
