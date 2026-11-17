import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/pick_image_web_batch.dart';

import '../../helpers/fake_platform_file.dart';
import 'image_fixtures.dart';

void main() {
  test('reads each picked file and types it', () async {
    final result = await readWebImageBatch(
      [FakePlatformFile(name: 'a.png', bytes: onePixelPng)],
      revokeObjectUrl: (_) {},
    );

    expect(result.images.single.bytes, onePixelPng);
    expect(result.images.single.mimeType, 'image/png');
    expect(result.errors, isEmpty);
  });

  test('reports a file the browser cannot read and keeps the rest', () async {
    final error = StateError('NotReadableError');

    final result = await readWebImageBatch(
      [
        FakePlatformFile(name: 'bad.png', readError: error),
        FakePlatformFile(name: 'good.png', bytes: onePixelPng),
      ],
      revokeObjectUrl: (_) {},
    );

    expect(result.images.single.name, 'good.png');
    expect(result.errors.single.filename, 'bad.png');
    expect(result.errors.single.cause, same(error));
  });

  test('revokes every object URL, even after a failed read', () async {
    final revoked = <String>[];

    await readWebImageBatch(
      [
        FakePlatformFile(name: 'bad.png', readError: StateError('x')),
        FakePlatformFile(name: 'good.png', bytes: onePixelPng),
      ],
      revokeObjectUrl: revoked.add,
    );

    expect(revoked, [
      'blob:http://localhost/bad.png',
      'blob:http://localhost/good.png',
    ]);
  });

  test('revokes only blob URLs', () async {
    final revoked = <String>[];

    await readWebImageBatch(
      [FakePlatformFile(name: 'a.png', path: '/tmp/a.png')],
      revokeObjectUrl: revoked.add,
    );

    expect(revoked, isEmpty);
  });
}
