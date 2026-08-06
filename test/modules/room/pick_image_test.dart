import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/attachable_images.dart';
import 'package:soliplex_frontend/src/modules/room/pick_image.dart';

import 'image_fixtures.dart';

void main() {
  group('PickedImage.fromBytes', () {
    test('types an iPhone photo as HEIC however it is named', () {
      // The case the content-first rule exists for, end to end: a HEIC that
      // reached us under a .jpeg name must not be sent to the model as JPEG.
      // Passing the bytes to the sniffer is the decision under test — drop
      // them and this types by the name — and it rests on the sniffer carrying
      // HEIC magic, which is a property of a dependency and can be lost in a
      // bump. The other orderings this resolves are the sniffer's own
      // guarantees, and are its tests to keep.
      final image = PickedImage.fromBytes(
        name: 'IMG_0001.jpeg',
        bytes: heicHeader,
      );

      expect(image.mimeType, 'image/heic');
      expect(allowedInlineImageMimeTypes, isNot(contains(image.mimeType)));
    });

    test('leaves an image nothing can type as opaque bytes', () {
      // No allow-list carries this, so such a file is turned away rather than
      // sent as an image.
      final image = PickedImage.fromBytes(
        name: 'notes',
        bytes: Uint8List.fromList([1, 2, 3, 4]),
      );

      expect(image.mimeType, 'application/octet-stream');
    });
  });
}
