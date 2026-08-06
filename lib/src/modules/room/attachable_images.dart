import 'package:soliplex_agent/soliplex_agent.dart';

import 'pick_image.dart';

/// The image types a message may carry inline.
///
/// HEIC is absent even though an iPhone shoots it by default. Only iOS is asked
/// for a compatible representation (see [inlineImageCompressionQuality]), so an
/// iPhone's photo arrives as JPEG; nothing transcodes on any other platform, so
/// a HEIC picked there arrives as itself and is turned away. Either way the
/// model most likely cannot read it, and saying so gives the user something to
/// act on.
const allowedInlineImageMimeTypes = <String>{
  'image/png',
  'image/jpeg',
  'image/webp',
  'image/gif',
};

/// How many images one message may carry.
///
/// A backstop against a pathological payload rather than a dial to tune.
///
/// Applied when images are added, against the images the composer's text
/// already holds, so four picks of one image each meet the same ceiling as one
/// pick of four. It counts the text rather than the bytes the composer is
/// keeping: an image removed from the text keeps its bytes until a send or a
/// thread change, so that undoing the removal brings the image back rather
/// than a broken chip.
///
/// A placeholder left by a draft that came back from re-authentication without
/// its images is not counted. It carries no bytes, and it blocks the send until
/// it is removed, so charging it against the ceiling would only refuse a pick
/// the user is still free to make good on.
///
/// Nothing re-applies it when the message is sent, so copying an image's
/// character out of the text and pasting it carries that image twice. Left
/// that way on purpose — the ceiling is here to stop an accident, and a user
/// duplicating their own image is spending their own bandwidth.
const maxInlineImagesPerMessage = 4;

/// How many bytes of image one message may carry, counted before base64
/// inflates them by 4/3. Same backstop, applied and escapable the same way.
///
/// Sized against nothing in particular: the backend application sets no body
/// limit of its own, but a proxy in front of it may well, and this side cannot
/// see one.
const maxInlineImageBytesPerMessage = 15 * 1024 * 1024;

/// Why a picked image will not be attached.
enum ImageRejection {
  /// Not a type [allowedInlineImageMimeTypes] carries.
  unsupportedType,

  /// The message already holds [maxInlineImagesPerMessage].
  tooManyImages,

  /// Attaching it would put the message over [maxInlineImageBytesPerMessage].
  messageTooLarge,

  /// Nothing usable came back for it — the picker could not read its bytes, or
  /// read no bytes at all.
  unreadable,
}

/// A picked image that will not be attached, and why: the file's name as the
/// picker reported it, and the reason it is being turned away.
typedef RejectedImage = ({String name, ImageRejection reason});

/// What a pick yields once the message's limits are applied: the images to
/// attach, in selection order, and the ones turned away.
typedef AttachableImages = ({
  List<ImagePart> accepted,
  List<RejectedImage> rejected,
});

/// Splits [picked] into the images a message may carry and the ones it may not.
///
/// The limits are per message, not per pick, so [attached] is what the composer
/// already holds — four picks of one image each have to meet the same ceiling
/// as one pick of four. Taking the images rather than a count and a byte total
/// is what keeps those two from disagreeing with each other, or with the
/// composer.
///
/// Turns away one image at a time rather than the whole pick, so a selection
/// that runs past a limit still attaches what fits, in the order it was
/// selected. Never yields [ImageRejection.unreadable] for anything but an
/// image with no bytes; the picker owns the rest of that reason.
///
/// Never decodes an image, and never re-encodes one: an accepted image carries
/// the bytes the picker returned. Doing otherwise here would inflate a PNG,
/// strip a photo's EXIF, and flatten an animated GIF to a single frame — none
/// of it visible from the composer.
AttachableImages attachableImages(
  List<PickedImage> picked, {
  required Iterable<ImagePart> attached,
}) {
  final accepted = <ImagePart>[];
  final rejected = <RejectedImage>[];
  var count = attached.length;
  var bytes = attached.fold(0, (total, part) => total + part.bytes.length);

  for (final image in picked) {
    final reason = _rejectionFor(image, count: count, bytes: bytes);
    if (reason != null) {
      rejected.add((name: image.name, reason: reason));
      continue;
    }
    accepted.add(ImagePart(bytes: image.bytes, mimeType: image.mimeType));
    count++;
    bytes += image.bytes.length;
  }
  return (accepted: accepted, rejected: rejected);
}

ImageRejection? _rejectionFor(
  PickedImage image, {
  required int count,
  required int bytes,
}) {
  // An allowed type over no bytes still reaches the model as an image, and one
  // it can make nothing of. It also comes back from history as an attachment
  // that cannot be rebuilt, since a valid encoding of nothing is undecodable.
  //
  // Asked before the type, because an empty file has no content to be typed
  // by: its type is only ever its name's claim, so a zero-byte `photo.png`
  // would pass the allow-list and be reported as something other than what is
  // wrong with it.
  if (image.bytes.isEmpty) return ImageRejection.unreadable;
  if (!allowedInlineImageMimeTypes.contains(image.mimeType)) {
    return ImageRejection.unsupportedType;
  }
  if (count >= maxInlineImagesPerMessage) return ImageRejection.tooManyImages;
  if (bytes + image.bytes.length > maxInlineImageBytesPerMessage) {
    return ImageRejection.messageTooLarge;
  }
  return null;
}

/// Lists the first few names and counts whatever is left, so the sentence a
/// notice builds from this is the same length however large the pick was.
///
/// Naming every file is what this replaces: a pick of a folder of unsupported
/// images grew the notice, and with it the composer, until the text field and
/// the send button left the screen — the notice sits above the composer with
/// nothing to scroll it, so its height comes out of the conversation.
///
/// It names [maxInlineImagesPerMessage] of them because a pick that could have
/// been attached in full is worth naming in full; past that, the files were
/// never going to fit anyway. That ties this sentence's length to a ceiling
/// that exists for another reason — raising [maxInlineImagesPerMessage] far
/// would put the composer back off the screen, and would mean giving this a
/// bound of its own.
String _namesAndTheRest(List<String> names) =>
    names.length <= maxInlineImagesPerMessage
        ? names.join(', ')
        : '${names.take(maxInlineImagesPerMessage).join(', ')} '
            'and ${names.length - maxInlineImagesPerMessage} more';

/// What to tell the user about everything a pick turned away, or null when it
/// turned away nothing.
///
/// Names the files whose type or contents were the problem, since only the user
/// can pick something else — see [_namesAndTheRest] for how many; states a
/// limit once however many images ran into it, since naming them adds nothing
/// to a ceiling.
String? rejectedImagesNotice(List<RejectedImage> rejected) {
  if (rejected.isEmpty) return null;

  List<String> namesFor(ImageRejection reason) => rejected
      .where((image) => image.reason == reason)
      .map((image) => image.name)
      .toList();

  final unsupported = namesFor(ImageRejection.unsupportedType);
  final unreadable = namesFor(ImageRejection.unreadable);
  final megabytes = maxInlineImageBytesPerMessage ~/ (1024 * 1024);

  return [
    if (unsupported.isNotEmpty)
      unsupported.length == 1
          ? '${unsupported.single} is not a supported image.'
          : '${_namesAndTheRest(unsupported)} are not supported images.',
    // No singular form to pick between: unlike "is/are not supported" above,
    // this sentence reads the same however many files it names.
    if (unreadable.isNotEmpty)
      '${_namesAndTheRest(unreadable)} could not be read.',
    if (rejected.any((image) => image.reason == ImageRejection.tooManyImages))
      'A message carries at most $maxInlineImagesPerMessage images.',
    if (rejected.any((image) => image.reason == ImageRejection.messageTooLarge))
      'Images must total at most $megabytes MB.',
  ].join(' ');
}
