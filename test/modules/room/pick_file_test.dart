import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
// ignore: implementation_imports
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/pick_file.dart';

class _FakeFilePicker extends FilePickerPlatform {
  _FakeFilePicker.result(FilePickerResult this._result) : _thrown = null;
  _FakeFilePicker.throwing(Object this._thrown) : _result = null;

  final FilePickerResult? _result;
  final Object? _thrown;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
  }) async {
    if (_thrown != null) throw _thrown;
    return _result;
  }
}

void main() {
  late FilePickerPlatform originalPlatform;

  setUp(() {
    originalPlatform = FilePickerPlatform.instance;
  });

  tearDown(() {
    FilePickerPlatform.instance = originalPlatform;
  });

  test('returns null when user cancels the picker', () async {
    FilePickerPlatform.instance = _FakeFilePicker.result(
      FilePickerResult(const []),
    );
    expect(await pickFile(), isNull);
  });

  test('wraps picker plugin errors in PickFilePickerException', () async {
    final cause = StateError('plugin not available');
    FilePickerPlatform.instance = _FakeFilePicker.throwing(cause);

    expect(
      pickFile(),
      throwsA(
        isA<PickFilePickerException>()
            .having((e) => e.cause, 'cause', cause)
            .having((e) => e.filename, 'filename', isNull),
      ),
    );
  });

  test('throws PickFilePickerException on native when picker returns no path',
      () async {
    FilePickerPlatform.instance = _FakeFilePicker.result(
      FilePickerResult([PlatformFile(name: 'x.pdf', size: 0)]),
    );

    expect(
      pickFile(),
      throwsA(
        isA<PickFilePickerException>()
            .having((e) => e.filename, 'filename', 'x.pdf')
            .having((e) => e.cause, 'cause', isA<StateError>()),
      ),
    );
  });

  test('returns PickedFile with size and MIME for native path-based pick',
      () async {
    final tempFile = await File(
      '${Directory.systemTemp.path}/pick_file_test_${DateTime.now().microsecondsSinceEpoch}.pdf',
    ).create();
    addTearDown(() async {
      if (tempFile.existsSync()) await tempFile.delete();
    });
    final fileContents = utf8.encode('hello world');
    await tempFile.writeAsBytes(fileContents);

    FilePickerPlatform.instance = _FakeFilePicker.result(
      FilePickerResult([
        PlatformFile(
          name: 'doc.pdf',
          size: fileContents.length,
          path: tempFile.path,
        ),
      ]),
    );

    final picked = await pickFile();
    expect(picked, isNotNull);
    expect(picked!.name, 'doc.pdf');
    expect(picked.size, fileContents.length);
    expect(picked.mimeType, 'application/pdf');

    // openStream reads bytes lazily and produces the file contents.
    final emitted = await picked
        .openStream()
        .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
    expect(emitted, fileContents);
  });

  group('pickerErrorMessage', () {
    test('RangeError cause surfaces as a browser-heap message', () {
      final error = PickFilePickerException(
        cause: RangeError('Maximum allowed length'),
      );
      expect(
        pickerErrorMessage(error),
        'Selection is too large to load in the browser.',
      );
    });

    test('other causes fall through to generic picker message', () {
      final error = PickFilePickerException(
        cause: StateError('plugin not available'),
      );
      expect(pickerErrorMessage(error), 'Could not open file picker');
    });
  });

  test('openStream factory is re-callable for retry', () async {
    final tempFile = await File(
      '${Directory.systemTemp.path}/pick_file_retry_${DateTime.now().microsecondsSinceEpoch}.bin',
    ).create();
    addTearDown(() async {
      if (tempFile.existsSync()) await tempFile.delete();
    });
    final fileContents = [0x01, 0x02, 0x03, 0x04];
    await tempFile.writeAsBytes(fileContents);

    FilePickerPlatform.instance = _FakeFilePicker.result(
      FilePickerResult([
        PlatformFile(
          name: 'retry.bin',
          size: fileContents.length,
          path: tempFile.path,
        ),
      ]),
    );

    final picked = await pickFile();

    final first = await picked!
        .openStream()
        .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
    final second = await picked
        .openStream()
        .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));

    expect(first, fileContents);
    expect(second, fileContents);
  });
}
