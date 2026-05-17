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

class _FakeFolderPicker extends FilePickerPlatform {
  _FakeFolderPicker(this._directoryPath);

  final String? _directoryPath;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) async {
    return _directoryPath;
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

  test('pickFiles returns null when user cancels the picker', () async {
    FilePickerPlatform.instance = _FakeFilePicker.result(
      FilePickerResult(const []),
    );
    expect(await pickFiles(), isNull);
  });

  test('pickFiles wraps whole-picker plugin errors in PickFilePickerException',
      () async {
    final cause = StateError('plugin not available');
    FilePickerPlatform.instance = _FakeFilePicker.throwing(cause);

    expect(
      pickFiles(),
      throwsA(
        isA<PickFilePickerException>().having((e) => e.cause, 'cause', cause),
      ),
    );
  });

  test('pickFiles returns a single PickedFile when one file is picked',
      () async {
    final tempFile = await File(
      '${Directory.systemTemp.path}/pick_files_single_${DateTime.now().microsecondsSinceEpoch}.pdf',
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

    final result = await pickFiles();
    expect(result, isNotNull);
    expect(result!.errors, isEmpty);
    expect(result.files, hasLength(1));

    final picked = result.files.single;
    expect(picked.name, 'doc.pdf');
    expect(picked.size, fileContents.length);
    expect(picked.mimeType, 'application/pdf');

    final emitted = await picked
        .openStream()
        .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
    expect(emitted, fileContents);
  });

  test('pickFiles returns multiple PickedFiles when many files are picked',
      () async {
    final fileA = await File(
      '${Directory.systemTemp.path}/pick_files_multi_a_${DateTime.now().microsecondsSinceEpoch}.txt',
    ).create();
    final fileB = await File(
      '${Directory.systemTemp.path}/pick_files_multi_b_${DateTime.now().microsecondsSinceEpoch}.txt',
    ).create();
    addTearDown(() async {
      if (fileA.existsSync()) await fileA.delete();
      if (fileB.existsSync()) await fileB.delete();
    });
    final aBytes = utf8.encode('aaa');
    final bBytes = utf8.encode('bbbb');
    await fileA.writeAsBytes(aBytes);
    await fileB.writeAsBytes(bBytes);

    FilePickerPlatform.instance = _FakeFilePicker.result(
      FilePickerResult([
        PlatformFile(name: 'a.txt', size: aBytes.length, path: fileA.path),
        PlatformFile(name: 'b.txt', size: bBytes.length, path: fileB.path),
      ]),
    );

    final result = await pickFiles();
    expect(result, isNotNull);
    expect(result!.errors, isEmpty);
    expect(result.files.map((f) => f.name), ['a.txt', 'b.txt']);
    expect(result.files.map((f) => f.size), [aBytes.length, bBytes.length]);

    final emittedA = await result.files[0]
        .openStream()
        .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
    final emittedB = await result.files[1]
        .openStream()
        .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
    expect(emittedA, aBytes);
    expect(emittedB, bBytes);
  });

  test(
      'pickFiles routes a per-file null-path failure to errors '
      'without aborting siblings', () async {
    final goodFile = await File(
      '${Directory.systemTemp.path}/pick_files_partial_${DateTime.now().microsecondsSinceEpoch}.txt',
    ).create();
    addTearDown(() async {
      if (goodFile.existsSync()) await goodFile.delete();
    });
    final goodBytes = utf8.encode('ok');
    await goodFile.writeAsBytes(goodBytes);

    FilePickerPlatform.instance = _FakeFilePicker.result(
      FilePickerResult([
        // First file: native invariant violation — no path.
        PlatformFile(name: 'broken.bin', size: 10),
        // Second file: works.
        PlatformFile(
          name: 'good.txt',
          size: goodBytes.length,
          path: goodFile.path,
        ),
      ]),
    );

    final result = await pickFiles();
    expect(result, isNotNull);
    expect(result!.files, hasLength(1));
    expect(result.files.single.name, 'good.txt');

    expect(result.errors, hasLength(1));
    expect(result.errors.single.filename, 'broken.bin');
    expect(result.errors.single.cause, isA<StateError>());
  });

  group('mangleRelativePath', () {
    test('joins POSIX-separated segments with __ and prepends rootName', () {
      expect(
        mangleRelativePath('myproject', 'src/main.dart'),
        'myproject__src__main.dart',
      );
    });

    test('joins Windows-separated segments with __ as well', () {
      expect(
        mangleRelativePath('myproject', r'src\nested\main.dart'),
        'myproject__src__nested__main.dart',
      );
    });

    test('handles mixed separators in a single path', () {
      expect(
        mangleRelativePath('myproject', r'a/b\c/d.txt'),
        'myproject__a__b__c__d.txt',
      );
    });

    test('flat filename keeps single segment', () {
      expect(
        mangleRelativePath('myproject', 'README.md'),
        'myproject__README.md',
      );
    });

    test('rejects ".." segments with FormatException', () {
      expect(
        () => mangleRelativePath('myproject', '../etc/passwd'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => mangleRelativePath('myproject', r'src\..\secret.txt'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects "." segments with FormatException', () {
      expect(
        () => mangleRelativePath('myproject', 'src/./file.txt'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects empty rootName', () {
      expect(
        () => mangleRelativePath('', 'file.txt'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects all-empty / leading-separator relative path', () {
      expect(
        () => mangleRelativePath('myproject', ''),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => mangleRelativePath('myproject', '///'),
        throwsA(isA<FormatException>()),
      );
    });

    test('strips leading/trailing/repeated separators', () {
      expect(
        mangleRelativePath('myproject', '/src//main.dart/'),
        'myproject__src__main.dart',
      );
    });
  });

  group('pickFolder', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('pick_folder_test_');
    });

    tearDown(() async {
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('returns null when user cancels (no folder selected)', () async {
      FilePickerPlatform.instance = _FakeFolderPicker(null);
      expect(await pickFolder(), isNull);
    });

    test('returns null when folder contains only dotfiles', () async {
      final folder = await Directory('${tempRoot.path}/empty_proj').create();
      await File('${folder.path}/.DS_Store').writeAsString('mac junk');
      await File('${folder.path}/.gitignore').writeAsString('node_modules');
      FilePickerPlatform.instance = _FakeFolderPicker(folder.path);

      expect(await pickFolder(), isNull);
    });

    test(
      'mangles file names using folder basename as root and walks recursively',
      () async {
        final folder = await Directory('${tempRoot.path}/myproject').create();
        await File('${folder.path}/README.md').writeAsString('readme');
        final src = await Directory('${folder.path}/src').create();
        await File('${src.path}/main.dart').writeAsString('void main(){}');
        FilePickerPlatform.instance = _FakeFolderPicker(folder.path);

        final result = await pickFolder();
        expect(result, isNotNull);
        expect(result!.errors, isEmpty);

        final names = result.files.map((f) => f.name).toList()..sort();
        expect(names, [
          'myproject__README.md',
          'myproject__src__main.dart',
        ]);

        // Each PickedFile re-streams its underlying file bytes.
        final readme =
            result.files.firstWhere((f) => f.name == 'myproject__README.md');
        final bytes = await readme
            .openStream()
            .fold<List<int>>(<int>[], (acc, c) => acc..addAll(c));
        expect(utf8.decode(bytes), 'readme');
      },
    );

    test('skips dotfiles in the root and files under dot-prefixed dirs',
        () async {
      final folder = await Directory('${tempRoot.path}/project_x').create();
      await File('${folder.path}/keep.txt').writeAsString('keep');
      await File('${folder.path}/.DS_Store').writeAsString('mac junk');
      final dotGit = await Directory('${folder.path}/.git').create();
      await File('${dotGit.path}/HEAD').writeAsString('ref: refs/heads/main');
      FilePickerPlatform.instance = _FakeFolderPicker(folder.path);

      final result = await pickFolder();
      expect(result, isNotNull);
      expect(result!.errors, isEmpty);
      expect(result.files.map((f) => f.name), ['project_x__keep.txt']);
    });
  });

  group('pickerErrorMessage', () {
    test('RangeError cause surfaces as a browser-heap message', () {
      expect(
        pickerErrorMessage(RangeError('Maximum allowed length')),
        'Selection is too large to load in the browser.',
      );
    });

    test('other causes fall through to generic picker message', () {
      expect(
        pickerErrorMessage(StateError('plugin not available')),
        'Could not open file picker',
      );
    });
  });
}
