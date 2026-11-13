import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/pick_file.dart';
import 'package:soliplex_frontend/src/modules/room/pick_image.dart';

import '../../helpers/fake_platform_file.dart';
import 'image_fixtures.dart';

/// Records what the picker was asked for, so the arguments that decide whether
/// an image is re-encoded can be asserted without a device.
class _RecordingPicker extends FilePickerPlatform {
  _RecordingPicker(this._files);

  /// The batch to answer with; an empty one stands in for a cancel.
  final List<PlatformFile> _files;

  FileType? type;
  int? compressionQuality;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    this.type = type;
    this.compressionQuality = compressionQuality;
    return _files;
  }
}

void main() {
  late FilePickerPlatform originalPlatform;
  late Directory tempDir;

  setUp(() {
    originalPlatform = FilePickerPlatform.instance;
    tempDir = Directory.systemTemp.createTempSync('pick_image_test');
  });

  tearDown(() {
    FilePickerPlatform.instance = originalPlatform;
    debugDefaultTargetPlatformOverride = null;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File writeImage(String name) =>
      File('${tempDir.path}/$name')..writeAsBytesSync(onePixelPng);

  PlatformFile platformFile(File file) => FakePlatformFile(
        name: file.uri.pathSegments.last,
        path: file.path,
        size: file.lengthSync(),
      );

  _RecordingPicker install(List<PlatformFile> files) {
    final picker = _RecordingPicker(files);
    FilePickerPlatform.instance = picker;
    return picker;
  }

  // A pick that lost every item fails as a whole on both mobile platforms
  // (see the throwing case below), so an empty answer is only ever a cancel.
  test('answers a cancel with nothing at all', () async {
    install([]);

    expect(await pickImages(), isNull);
  });

  // The picker reads one number two unrelated ways: on iOS any non-zero value
  // asks for a compatible representation, which is what turns an iPhone's HEIC
  // into a JPEG; on Android the same number is a real re-encode quality handed
  // to the platform encoder. `compressionQuality` and `type` both have silent
  // defaults, so dropping either changes what the user's image is — or which
  // chooser opens — without failing to compile.
  test('asks iOS for a compatible representation', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final picker = install([platformFile(writeImage('a.png'))]);

    await pickImages();

    expect(picker.compressionQuality, greaterThan(0));
    expect(picker.type, FileType.image);
  });

  test('leaves every other platform re-encoding nothing', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final picker = install([platformFile(writeImage('a.png'))]);

    await pickImages();

    expect(picker.compressionQuality, 0);
  });

  test('reads the picked bytes and types them', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    install([platformFile(writeImage('a.png'))]);

    final result = await pickImages();

    expect(result!.images.single.bytes, onePixelPng);
    expect(result.images.single.mimeType, 'image/png');
    expect(result.errors, isEmpty);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    test('discards the copy the ${platform.name} picker made', () async {
      // Otherwise it waits in temporary storage for the next launch's sweep.
      debugDefaultTargetPlatformOverride = platform;
      final file = writeImage('a.png');
      install([platformFile(file)]);

      await pickImages();

      expect(file.existsSync(), isFalse);
    });
  }

  test('discards the copy even when it cannot be read', () async {
    // The read most likely to fail is of the largest image, so leaving the
    // copy behind on that path would hold the worst case until the next
    // launch.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final file = writeImage('a.png');
    // Unreadable but still deletable: deleting answers to the directory's
    // permissions, not the file's.
    Process.runSync('chmod', ['000', file.path]);
    install([platformFile(file)]);

    final result = await pickImages();

    expect(result!.errors.single.filename, 'a.png');
    expect(
      file.existsSync(),
      isFalse,
      reason: 'the picker copy should be discarded even after a failed read',
    );
  },
      skip: Platform.isWindows || Process.runSync('id', ['-u']).stdout == '0\n'
          ? 'needs POSIX permissions and a non-root user to make a read fail'
          : null);

  test('leaves the picked file alone where it is the user\'s own', () async {
    // On desktop the path is the file the user chose, not a copy of it.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final file = writeImage('a.png');
    install([platformFile(file)]);

    await pickImages();

    expect(file.existsSync(), isTrue);
  });

  test('reports a file it cannot read and keeps the rest of the batch',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final readable = writeImage('good.png');
    install([
      FakePlatformFile(
        name: 'gone.png',
        path: '${tempDir.path}/gone.png',
        size: 1,
      ),
      platformFile(readable),
    ]);

    final result = await pickImages();

    expect(result!.images.single.bytes, onePixelPng);
    expect(result.errors.single.filename, 'gone.png');
    expect(result.errors.single.cause, isA<FileSystemException>());
  });

  test('reports a file the picker gave no path for', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    install([FakePlatformFile(name: 'nopath.png', size: 1)]);

    final result = await pickImages();

    expect(result!.images, isEmpty);
    expect(result.errors.single.filename, 'nopath.png');
  });

  test('wraps a whole-picker failure', () async {
    FilePickerPlatform.instance = _ThrowingPicker();

    expect(pickImages(), throwsA(isA<PickFilePickerException>()));
  });
}

class _ThrowingPicker extends FilePickerPlatform {
  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async =>
      throw StateError('plugin missing');
}
