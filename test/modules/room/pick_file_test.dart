import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_folder_picker/soliplex_folder_picker.dart';
import 'package:soliplex_frontend/src/modules/room/pick_file.dart';
import 'package:soliplex_frontend/src/modules/room/pick_file_impl.dart'
    show folderPicker;

import '../../helpers/fake_platform_file.dart';

class _FakeFilePicker extends FilePickerPlatform {
  _FakeFilePicker.result(List<PlatformFile> this._result) : _thrown = null;
  _FakeFilePicker.throwing(Object this._thrown) : _result = null;

  final List<PlatformFile>? _result;
  final Object? _thrown;

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
    if (_thrown != null) throw _thrown;
    return _result!;
  }
}

class _FakeFolderPicker extends FilePickerPlatform {
  _FakeFolderPicker(this._directoryPath) : _thrown = null;
  _FakeFolderPicker.throwing(Object this._thrown) : _directoryPath = null;

  final String? _directoryPath;
  final Object? _thrown;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    if (_thrown != null) throw _thrown;
    return _directoryPath;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FilePickerPlatform originalPlatform;

  setUp(() {
    originalPlatform = FilePickerPlatform.instance;
  });

  tearDown(() {
    FilePickerPlatform.instance = originalPlatform;
  });

  test('pickFiles returns null when user cancels the picker', () async {
    FilePickerPlatform.instance = _FakeFilePicker.result(const []);
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

    FilePickerPlatform.instance = _FakeFilePicker.result([
      FakePlatformFile(
        name: 'doc.pdf',
        size: fileContents.length,
        path: tempFile.path,
      ),
    ]);

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

    FilePickerPlatform.instance = _FakeFilePicker.result([
      FakePlatformFile(name: 'a.txt', size: aBytes.length, path: fileA.path),
      FakePlatformFile(name: 'b.txt', size: bBytes.length, path: fileB.path),
    ]);

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

    FilePickerPlatform.instance = _FakeFilePicker.result([
      // First file: native invariant violation — no path.
      FakePlatformFile(name: 'broken.bin', size: 10),
      // Second file: works.
      FakePlatformFile(
        name: 'good.txt',
        size: goodBytes.length,
        path: goodFile.path,
      ),
    ]);

    final result = await pickFiles();
    expect(result, isNotNull);
    expect(result!.files, hasLength(1));
    expect(result.files.single.name, 'good.txt');

    expect(result.errors, hasLength(1));
    expect(result.errors.single.filename, 'broken.bin');
    expect(result.errors.single.cause, isA<StateError>());
  });

  test('takes the size the platform reported without reading the file',
      () async {
    // Nothing exists at the path, so a size read from disk would fail.
    FilePickerPlatform.instance = _FakeFilePicker.result([
      FakePlatformFile(
        name: 'reported.bin',
        path: '${Directory.systemTemp.path}/pick_files_never_written.bin',
        size: 42,
      ),
    ]);

    final result = await pickFiles();

    expect(result!.errors, isEmpty);
    expect(result.files.single.size, 42);
  });

  group('a pick whose result carries no size', () {
    // Every pick on Windows and Linux: the size is read from the file.
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('pick_files_size'));
    tearDown(() => dir.deleteSync(recursive: true));

    File write(String name, List<int> bytes) =>
        File('${dir.path}/$name')..writeAsBytesSync(bytes);

    test('takes the size from the file', () async {
      final file = write('a.txt', utf8.encode('seven b'));
      FilePickerPlatform.instance = _FakeFilePicker.result([
        FakePlatformFile(name: 'a.txt', path: file.path),
      ]);

      final result = await pickFiles();

      expect(result!.errors, isEmpty);
      expect(result.files.single.size, 7);
    });

    test('accepts an empty file', () async {
      final file = write('empty.txt', const []);
      FilePickerPlatform.instance = _FakeFilePicker.result([
        FakePlatformFile(name: 'empty.txt', path: file.path),
      ]);

      final result = await pickFiles();

      expect(result!.errors, isEmpty);
      expect(result.files.single.size, 0);
    });

    test(
        'reports a file whose size cannot be read, with the reason, and '
        'keeps the rest of the batch', () async {
      // The upload's Content-Length needs the size, so that file cannot go
      // up; the file system's error says why.
      final good = write('good.txt', utf8.encode('ok'));
      FilePickerPlatform.instance = _FakeFilePicker.result([
        FakePlatformFile(name: 'gone.bin', path: '${dir.path}/gone.bin'),
        FakePlatformFile(name: 'good.txt', path: good.path),
      ]);

      final result = await pickFiles();

      expect(result!.files.single.name, 'good.txt');
      expect(result.files.single.size, 2);
      expect(result.errors.single.filename, 'gone.bin');
      expect(result.errors.single.cause, isA<FileSystemException>());
    });
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
    late SoliplexFolderPicker originalFolderPicker;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('pick_folder_test_');
      // Tests run as Android; these cover the path-based picker the other
      // platforms use.
      originalFolderPicker = folderPicker;
      folderPicker = SoliplexFolderPicker(
        platform: TargetPlatform.linux,
        isWeb: false,
      );
    });

    tearDown(() async {
      folderPicker = originalFolderPicker;
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('returns null when user cancels (no folder selected)', () async {
      FilePickerPlatform.instance = _FakeFolderPicker(null);
      expect(await pickFolder(), isNull);
    });

    test('wraps a failing directory picker in PickFilePickerException',
        () async {
      final error = Exception('picker exploded');
      FilePickerPlatform.instance = _FakeFolderPicker.throwing(error);

      await expectLater(
        pickFolder(),
        throwsA(
          isA<PickFilePickerException>()
              .having((e) => e.cause, 'cause', same(error)),
        ),
      );
    });

    test('wraps a folder it cannot list in PickFilePickerException', () async {
      // What iOS answers for a folder picked outside the app's own storage:
      // a path the app is not allowed to list.
      FilePickerPlatform.instance =
          _FakeFolderPicker('${tempRoot.path}/not_listable');

      await expectLater(
        pickFolder(),
        throwsA(
          isA<PickFilePickerException>()
              .having((e) => e.cause, 'cause', isA<FileSystemException>()),
        ),
      );
    });

    test('reports a folder that holds only dotfiles', () async {
      final folder = await Directory('${tempRoot.path}/empty_proj').create();
      await File('${folder.path}/.DS_Store').writeAsString('mac junk');
      await File('${folder.path}/.gitignore').writeAsString('node_modules');
      FilePickerPlatform.instance = _FakeFolderPicker(folder.path);

      final result = (await pickFolder())!;

      expect(result.files, isEmpty);
      expect(result.errors.single.filename, 'empty_proj');
      expect(result.errors.single.cause, isA<NoFilesInFolderError>());
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

  group('pickFolder through the document picker', () {
    const channel = MethodChannel('test/folder_picker');
    late SoliplexFolderPicker originalFolderPicker;
    final calls = <MethodCall>[];

    void answerPick(Object? folder) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'pick' => folder,
          'open' => 1,
          'read' => calls.where((c) => c.method == 'read').length == 1
              ? Uint8List.fromList(utf8.encode('alpha'))
              : null,
          _ => null,
        };
      });
    }

    setUp(() {
      calls.clear();
      originalFolderPicker = folderPicker;
      folderPicker = SoliplexFolderPicker(
        channel: channel,
        platform: TargetPlatform.android,
        isWeb: false,
      );
      // Reaching the path-based picker would be the bug under test.
      FilePickerPlatform.instance =
          _FakeFolderPicker.throwing(StateError('path picker used'));
    });

    tearDown(() {
      folderPicker = originalFolderPicker;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('returns null when the user cancels', () async {
      answerPick(null);
      expect(await pickFolder(), isNull);
    });

    test('names, filters and streams the files the picker lists', () async {
      answerPick({
        'name': 'testdir',
        'files': [
          {'path': 'a.txt', 'uri': 'content://t/a', 'size': 5},
          {'path': 'sub/b.md', 'uri': 'content://t/b', 'size': 3},
          {'path': '.hidden', 'uri': 'content://t/h', 'size': 1},
          {'path': '.git/HEAD', 'uri': 'content://t/g', 'size': 1},
        ],
      });

      final result = (await pickFolder())!;

      expect(result.errors, isEmpty);
      expect(
        result.files.map((f) => (f.name, f.size, f.mimeType)),
        [
          ('testdir__a.txt', 5, 'text/plain'),
          ('testdir__sub__b.md', 3, 'text/markdown'),
        ],
      );
      final bytes = await result.files.first
          .openStream()
          .fold<List<int>>(<int>[], (acc, c) => acc..addAll(c));
      expect(utf8.decode(bytes), 'alpha');
      expect(
        calls.firstWhere((c) => c.method == 'open').arguments,
        {'uri': 'content://t/a'},
      );
    });

    test('reports a file the picker gives no size for', () async {
      answerPick({
        'name': 'testdir',
        'files': [
          {'path': 'a.txt', 'uri': 'content://t/a', 'size': 5},
          {'path': 'odd.bin', 'uri': 'content://t/o', 'size': null},
        ],
      });

      final result = (await pickFolder())!;

      expect(result.files.map((f) => f.name), ['testdir__a.txt']);
      expect(result.errors.single.filename, 'odd.bin');
      expect(result.errors.single.cause, isA<StateError>());
    });

    test('reports a folder with nothing to upload', () async {
      answerPick({'name': 'testdir', 'files': <Object?>[]});

      final result = (await pickFolder())!;

      expect(result.files, isEmpty);
      expect(result.errors.single.filename, 'testdir');
      expect(result.errors.single.cause, isA<NoFilesInFolderError>());
    });

    test('wraps a failing picker in PickFilePickerException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'list_failed'),
      );

      await expectLater(
        pickFolder(),
        throwsA(
          isA<PickFilePickerException>()
              .having((e) => e.cause, 'cause', isA<PlatformException>()),
        ),
      );
    });
  });

  group('pickerErrorMessage', () {
    test('iOS load_failed says the files could not load, naming iCloud', () {
      expect(
        pickerErrorMessage(PlatformException(code: 'load_failed')),
        'Could not load the picked files. '
        'If they are in iCloud, check your connection.',
      );
    });

    test('Android unknown_path says the files could not load', () {
      expect(
        pickerErrorMessage(PlatformException(code: 'unknown_path')),
        'Could not load the picked files.',
      );
    });

    test('another platform error is the picker failing to open', () {
      expect(
        pickerErrorMessage(PlatformException(code: 'already_active')),
        'Could not open file picker',
      );
    });

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

  group('pickedFileErrorMessage', () {
    test('an empty folder says so', () {
      expect(
        pickedFileErrorMessage(const NoFilesInFolderError()),
        'No files to upload in this folder.',
      );
    });

    test('RangeError cause surfaces as a browser-heap message', () {
      expect(
        pickedFileErrorMessage(RangeError('Maximum allowed length')),
        'Selection is too large to load in the browser.',
      );
    });

    test('an unreadable file says so', () {
      expect(
        pickedFileErrorMessage(
          const FileSystemException('Cannot open file', '/x/a.txt'),
        ),
        'Could not read this file.',
      );
    });

    test('a file with no path says so', () {
      expect(
        pickedFileErrorMessage(StateError('picker returned no path for a')),
        'Could not read this file.',
      );
    });
  });
}
