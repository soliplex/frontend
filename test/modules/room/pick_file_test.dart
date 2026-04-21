import 'dart:typed_data';

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

  test('wraps picker errors in PickFilePickerException', () async {
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

  test(
    'throws PickFilePickerException when picker returns neither bytes nor '
    'path',
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
    },
  );

  test('returns PickedFile with bytes and derived MIME when bytes present',
      () async {
    FilePickerPlatform.instance = _FakeFilePicker.result(
      FilePickerResult([
        PlatformFile(
          name: 'doc.pdf',
          size: 3,
          bytes: Uint8List.fromList(const [1, 2, 3]),
        ),
      ]),
    );

    final picked = await pickFile();

    expect(picked, isNotNull);
    expect(picked!.name, 'doc.pdf');
    expect(picked.bytes, [1, 2, 3]);
    expect(picked.mimeType, 'application/pdf');
  });
}
