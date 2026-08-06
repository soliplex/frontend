import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/room/attachable_images.dart';
import 'package:soliplex_frontend/src/modules/room/pick_image.dart';

import 'image_fixtures.dart';

PickedImage _picked(
  String name,
  String mimeType, {
  int bytes = 8,
  Uint8List? content,
}) =>
    PickedImage(
      name: name,
      mimeType: mimeType,
      bytes: content ?? Uint8List(bytes),
    );

/// An image the composer already holds, standing in for prior state.
ImagePart _attached({int bytes = 8}) =>
    ImagePart(bytes: Uint8List(bytes), mimeType: 'image/png');

AttachableImages _attach(
  List<PickedImage> picked, {
  Iterable<ImagePart> attached = const [],
}) =>
    attachableImages(picked, attached: attached);

void main() {
  group('attachableImages', () {
    test('turns away a type the allow-list does not carry', () {
      final result = _attach([
        _picked('shot.png', 'image/png'),
        _picked('scan.tiff', 'image/tiff'),
        _picked('photo.HEIC', 'image/heic'),
        _picked('README', 'application/octet-stream'),
      ]);

      expect(result.accepted, hasLength(1));
      expect(
        result.rejected,
        const [
          (name: 'scan.tiff', reason: ImageRejection.unsupportedType),
          (name: 'photo.HEIC', reason: ImageRejection.unsupportedType),
          (name: 'README', reason: ImageRejection.unsupportedType),
        ],
      );
    });

    test('counts against what the composer already holds, not just this pick',
        () {
      // Four picks of one image each must run into the same ceiling as one
      // pick of four.
      final result = _attach(
        [_picked('a.png', 'image/png'), _picked('b.png', 'image/png')],
        attached: [
          for (var i = 0; i < maxInlineImagesPerMessage - 1; i++) _attached(),
        ],
      );

      expect(result.accepted, hasLength(1));
      expect(result.rejected.single.name, 'b.png');
      expect(result.rejected.single.reason, ImageRejection.tooManyImages);
    });

    test('attaches what fits and turns away only the overflow', () {
      final result = _attach([
        for (var i = 0; i < maxInlineImagesPerMessage + 2; i++)
          _picked('image$i.png', 'image/png'),
      ]);

      expect(
        result.accepted,
        hasLength(maxInlineImagesPerMessage),
        reason: 'a selection past the limit still attaches what fits',
      );
      expect(result.rejected.map((r) => r.name), [
        'image$maxInlineImagesPerMessage.png',
        'image${maxInlineImagesPerMessage + 1}.png',
      ]);
    });

    test('spends no part of the message on an image it turned away', () {
      // An image that is refused must leave the ceiling where it found it, or
      // a pick with one bad file in it silently costs the user a good one.
      final result = _attach([
        _picked('scan.tiff', 'image/tiff'),
        _picked('empty.png', 'image/png', bytes: 0),
        for (var i = 0; i < maxInlineImagesPerMessage; i++)
          _picked('image$i.png', 'image/png'),
      ]);

      expect(result.accepted, hasLength(maxInlineImagesPerMessage));
      expect(
        result.rejected.map((r) => r.name),
        ['scan.tiff', 'empty.png'],
      );
    });

    test('turns away an image that would put the message over the byte cap',
        () {
      final result = _attach([
        _picked('big.png', 'image/png', bytes: maxInlineImageBytesPerMessage),
        _picked('one-too-many.png', 'image/png', bytes: 1),
      ]);

      expect(result.accepted, hasLength(1));
      expect(result.rejected.single.reason, ImageRejection.messageTooLarge);
    });

    test('counts bytes the composer already holds toward the cap', () {
      final result = _attach(
        [_picked('small.png', 'image/png', bytes: 2)],
        attached: [_attached(bytes: maxInlineImageBytesPerMessage - 1)],
      );

      expect(result.accepted, isEmpty);
      expect(result.rejected.single.reason, ImageRejection.messageTooLarge);
    });

    test('accepts a pick that lands exactly on the byte cap', () {
      final result = _attach([
        _picked('exact.png', 'image/png', bytes: maxInlineImageBytesPerMessage),
      ]);

      expect(result.accepted, hasLength(1));
      expect(result.rejected, isEmpty);
    });

    test('keeps selection order', () {
      final result = _attach([
        _picked('1.gif', 'image/gif'),
        _picked('2.png', 'image/png'),
        _picked('3.webp', 'image/webp'),
      ]);

      expect(
        result.accepted.map((p) => p.mimeType),
        ['image/gif', 'image/png', 'image/webp'],
      );
    });

    // Keeps the passthrough test below honest about its own coverage: an
    // allowed type with no fixture is a format it silently never exercises.
    test('has a fixture for every type the allow-list carries', () {
      expect(onePixelImages.keys.toSet(), allowedInlineImageMimeTypes);
    });

    // The passthrough assertion below is only worth its name while the
    // fixtures decode: a transform that fell back to the original on a decode
    // failure would leave it green over bytes no encoder could have touched.
    // Deleting this test means deleting that claim from `image_fixtures.dart`
    // too — it is the only thing enforcing it.
    test('every fixture is an image an encoder could act on', () async {
      for (final MapEntry(key: mimeType, value: bytes)
          in onePixelImages.entries) {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 1, reason: mimeType);
        expect(frame.image.height, 1, reason: mimeType);
      }
    });

    // Validates and never transforms: no decode, no re-encode, no scaling. A
    // transform added here instead of behind the encoder would inflate a PNG,
    // strip a photo's EXIF, or flatten an animated GIF to one frame, none of it
    // visible from the composer.
    test('passes every allowed format through byte-identical', () {
      for (final MapEntry(key: mimeType, value: bytes)
          in onePixelImages.entries) {
        final picked = _picked('x', mimeType, content: bytes);
        final result = _attach([picked]);

        expect(result.accepted, hasLength(1), reason: mimeType);
        final part = result.accepted.single;
        expect(part.mimeType, mimeType);
        expect(part.bytes, equals(bytes), reason: mimeType);
      }
    });

    test('turns away an image with no bytes', () {
      // An allowed type over nothing still reaches the model as an image, and
      // comes back from history as an attachment that cannot be rebuilt.
      final result = _attach([_picked('empty.png', 'image/png', bytes: 0)]);

      expect(result.accepted, isEmpty);
      expect(result.rejected.single.reason, ImageRejection.unreadable);
    });
  });

  group('rejectedImagesNotice', () {
    test('says nothing when nothing was turned away', () {
      expect(rejectedImagesNotice(const []), isNull);
    });

    test('names the files whose type is not supported', () {
      expect(
        rejectedImagesNotice(const [
          (name: 'scan.tiff', reason: ImageRejection.unsupportedType),
        ]),
        'scan.tiff is not a supported image.',
      );
      expect(
        rejectedImagesNotice(const [
          (name: 'scan.tiff', reason: ImageRejection.unsupportedType),
          (name: 'a.heic', reason: ImageRejection.unsupportedType),
        ]),
        'scan.tiff, a.heic are not supported images.',
      );
    });

    test('states each limit once however many images ran into it', () {
      expect(
        rejectedImagesNotice(const [
          (name: 'a.png', reason: ImageRejection.tooManyImages),
          (name: 'b.png', reason: ImageRejection.tooManyImages),
        ]),
        'A message carries at most $maxInlineImagesPerMessage images.',
      );
      expect(
        rejectedImagesNotice(const [
          (name: 'a.png', reason: ImageRejection.messageTooLarge),
        ]),
        'Images must total at most 15 MB.',
      );
    });

    test('carries every reason a pick was turned away for', () {
      expect(
        rejectedImagesNotice(const [
          (name: 'a.tiff', reason: ImageRejection.unsupportedType),
          (name: 'b.png', reason: ImageRejection.unreadable),
          (name: 'c.png', reason: ImageRejection.tooManyImages),
        ]),
        'a.tiff is not a supported image. '
        'b.png could not be read. '
        'A message carries at most $maxInlineImagesPerMessage images.',
      );
    });

    test('counts the files past the first few rather than naming them all', () {
      // The notice sits above the composer with nothing to scroll it, so a
      // pick of a folder of unsupported files would otherwise grow the
      // composer until the text field and send button left the screen.
      expect(
        rejectedImagesNotice([
          for (var i = 0; i < 30; i++)
            (name: 'IMG_$i.tiff', reason: ImageRejection.unsupportedType),
        ]),
        'IMG_0.tiff, IMG_1.tiff, IMG_2.tiff, IMG_3.tiff and 26 more '
        'are not supported images.',
      );
      expect(
        rejectedImagesNotice([
          for (var i = 0; i < 6; i++)
            (name: 'IMG_$i.png', reason: ImageRejection.unreadable),
        ]),
        'IMG_0.png, IMG_1.png, IMG_2.png, IMG_3.png and 2 more '
        'could not be read.',
      );
    });

    test('names a pick that could have been attached in full', () {
      // At the ceiling there is nothing to elide: "and 1 more" would cost the
      // room the fourth name would have.
      expect(
        rejectedImagesNotice([
          for (var i = 0; i < maxInlineImagesPerMessage; i++)
            (name: 'IMG_$i.tiff', reason: ImageRejection.unsupportedType),
        ]),
        'IMG_0.tiff, IMG_1.tiff, IMG_2.tiff, IMG_3.tiff '
        'are not supported images.',
      );
    });
  });
}
