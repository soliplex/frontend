import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'package:soliplex_frontend/src/modules/room/workdir_controller.dart';
import 'package:soliplex_frontend/src/modules/room/workdir_files_status.dart';

class _MockApi extends Mock implements SoliplexApi {}

WorkdirFile _file(String name) =>
    WorkdirFile(filename: name, url: Uri.parse('https://example.test/$name'));

void main() {
  late _MockApi api;

  setUpAll(() {
    registerFallbackValue(CancelToken());
  });

  setUp(() {
    api = _MockApi();
  });

  WorkdirController build() => WorkdirController(api: api, roomId: 'room-1');

  group('thread files', () {
    void stubList(Future<List<WorkdirFile>> Function() answer,
        {String threadId = 't-1'}) {
      when(() => api.getThreadWorkdirFiles('room-1', threadId,
          cancelToken: any(named: 'cancelToken'))).thenAnswer((_) => answer());
    }

    List<String> names(WorkdirController c, String threadId) =>
        (c.files(threadId).value as WorkdirFilesLoaded)
            .files
            .map((f) => f.filename)
            .toList();

    test('starts Loading, then Loaded sorted by filename', () async {
      stubList(() async => [_file('b.csv'), _file('a.csv')]);
      final controller = build();
      addTearDown(controller.dispose);

      expect(controller.files('t-1').value, isA<WorkdirFilesLoading>());
      await controller.refresh('t-1');

      final status = controller.files('t-1').value as WorkdirFilesLoaded;
      expect(status.files.map((f) => f.filename), ['a.csv', 'b.csv']);
    });

    test('drops files under an ignored folder, at any depth', () async {
      stubList(() async => [
            _file('.git/HEAD'),
            _file('.git'),
            _file('src/__pycache__/main.cpython-312.pyc'),
            _file('a/b/.git/objects/ab/cd'),
            _file('.gitignore'),
            _file('git/notes.md'),
            _file('src/main.py'),
            _file('__pycache__.txt'),
            _file('a.git/b.txt'),
          ]);
      final controller = build();
      addTearDown(controller.dispose);

      await controller.refresh('t-1');

      expect(
        names(controller, 't-1'),
        [
          '.gitignore',
          '__pycache__.txt',
          'a.git/b.txt',
          'git/notes.md',
          'src/main.py',
        ],
      );
    });

    test('logs how many files a listing dropped, at debug', () async {
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));
      final level = LogManager.instance.minimumLevel;
      LogManager.instance.minimumLevel = LogLevel.debug;
      addTearDown(() => LogManager.instance.minimumLevel = level);
      stubList(() async => [
            _file('.git/HEAD'),
            _file('src/__pycache__/main.pyc'),
            _file('src/main.py'),
          ]);
      final controller = build();
      addTearDown(controller.dispose);

      await controller.refresh('t-1');

      final record = sink.records.singleWhere(
        (r) => r.message.startsWith('workdir list loaded'),
      );
      expect(record.level, LogLevel.debug);
      expect(record.message, contains('count=1'));
      expect(record.message, contains('ignored=2'));
    });

    test('a 404 before any load is an empty list', () async {
      stubList(() => throw const NotFoundException(
          message: 'no workspaces', resource: '/x'));
      final controller = build();
      addTearDown(controller.dispose);

      await controller.refresh('t-1');

      expect(names(controller, 't-1'), isEmpty);
    });

    test('a 404 after a load keeps the list', () async {
      var call = 0;
      stubList(() async {
        call++;
        if (call == 1) return [_file('a.csv')];
        throw const NotFoundException(message: 'gone', resource: '/x');
      });
      final controller = build();
      addTearDown(controller.dispose);

      await controller.refresh('t-1');
      await controller.refresh('t-1');

      expect(names(controller, 't-1'), ['a.csv']);
    });

    test('a retry stays Failed, marked retrying, until it lands', () async {
      final retry = Completer<List<WorkdirFile>>();
      var call = 0;
      stubList(() {
        call++;
        return call == 1
            ? Future.error(const NetworkException(message: 'down'))
            : retry.future;
      });
      final controller = build();
      addTearDown(controller.dispose);

      await controller.refresh('t-1');
      final failed = controller.files('t-1').value as WorkdirFilesFailed;
      expect(failed.retrying, isFalse);

      final retrying = controller.refresh('t-1');
      // Never Loading: the panel treats Loading as no content and would close.
      final during = controller.files('t-1').value as WorkdirFilesFailed;
      expect(during.retrying, isTrue);

      retry.complete([_file('a.csv')]);
      await retrying;
      expect(names(controller, 't-1'), ['a.csv']);
    });

    test('a retry that fails again is Failed, not retrying', () async {
      stubList(() => Future.error(const NetworkException(message: 'down')));
      final controller = build();
      addTearDown(controller.dispose);

      await controller.refresh('t-1');
      await controller.refresh('t-1');

      final failed = controller.files('t-1').value as WorkdirFilesFailed;
      expect(failed.retrying, isFalse);
    });

    test('a failure after a load keeps the list', () async {
      var call = 0;
      stubList(() async {
        call++;
        if (call == 1) return [_file('a.csv')];
        throw const NetworkException(message: 'down');
      });
      final controller = build();
      addTearDown(controller.dispose);

      await controller.refresh('t-1');
      await controller.refresh('t-1');

      expect(names(controller, 't-1'), ['a.csv']);
    });

    test('threads keep separate lists', () async {
      final tA = [
        [_file('a.csv')],
        [_file('a.csv'), _file('a2.csv')],
      ];
      stubList(() async => tA.removeAt(0), threadId: 't-A');
      stubList(() async => [_file('b.csv')], threadId: 't-B');
      final controller = build();
      addTearDown(controller.dispose);

      await controller.refresh('t-A');
      await controller.refresh('t-B');
      await controller.refresh('t-A');
      await controller.refresh('t-B');

      expect(names(controller, 't-A'), ['a.csv', 'a2.csv']);
      expect(names(controller, 't-B'), ['b.csv']);
    });

    test('a stray CancelledException is a failure, not a stuck retry',
        () async {
      var call = 0;
      stubList(() {
        call++;
        return Future.error(
          call == 1
              ? const NetworkException(message: 'down')
              : const CancelledException(),
        );
      });
      final controller = build();
      addTearDown(controller.dispose);

      await controller.refresh('t-1');
      await controller.refresh('t-1');

      final failed = controller.files('t-1').value as WorkdirFilesFailed;
      expect(failed.retrying, isFalse);
    });

    test('a newer refresh wins over an older one still in flight', () async {
      final first = Completer<List<WorkdirFile>>();
      var call = 0;
      when(() => api.getThreadWorkdirFiles('room-1', 't-1',
          cancelToken: any(named: 'cancelToken'))).thenAnswer((_) {
        call++;
        return call == 1 ? first.future : Future.value([_file('new.csv')]);
      });
      final controller = build();
      addTearDown(controller.dispose);

      final older = controller.refresh('t-1');
      await controller.refresh('t-1');
      first.complete([_file('old.csv')]);
      await older;

      expect(names(controller, 't-1'), ['new.csv']);
    });

    test('files() after dispose throws StateError', () {
      final controller = build()..dispose();

      expect(() => controller.files('t-1'), throwsStateError);
    });
  });

  group('folder toggles', () {
    test('are kept across a refresh', () async {
      when(() => api.getThreadWorkdirFiles('room-1', 't-1',
              cancelToken: any(named: 'cancelToken')))
          .thenAnswer((_) async => [_file('reports/a.csv')]);
      final controller = build();
      addTearDown(controller.dispose);
      await controller.refresh('t-1');

      controller.setFolderExpanded('t-1', 'reports', expanded: false);
      await controller.refresh('t-1');

      expect(controller.folderToggles('t-1').value, {'reports': false});
    });

    test('a toggle keeps the others', () {
      final controller = build();
      addTearDown(controller.dispose);

      controller.setFolderExpanded('t-1', 'reports', expanded: false);
      controller.setFolderExpanded('t-1', 'crm_app', expanded: false);

      expect(controller.folderToggles('t-1').value,
          {'reports': false, 'crm_app': false});
    });

    test('opening the folders of files opens only theirs', () {
      final controller = build();
      addTearDown(controller.dispose);
      controller.setFolderExpanded('t-1', 'a', expanded: false);
      controller.setFolderExpanded('t-1', 'b', expanded: false);

      controller.openFoldersOf('t-1', [_file('b/x.csv'), _file('root.txt')]);

      expect(controller.folderToggles('t-1').value, {'a': false, 'b': true});
    });

    test('opening the folders of a nested file opens every folder above it',
        () {
      final controller = build();
      addTearDown(controller.dispose);
      controller.setFolderExpanded('t-1', 'a', expanded: false);

      controller.openFoldersOf('t-1', [_file('a/b/c/x.csv')]);

      expect(controller.folderToggles('t-1').value,
          {'a': true, 'a/b': true, 'a/b/c': true});
    });

    test('closing folders closes each and keeps the others', () {
      final controller = build();
      addTearDown(controller.dispose);
      controller.setFolderExpanded('t-1', 'a', expanded: true);
      controller.setFolderExpanded('t-1', 'c', expanded: true);

      controller.closeFolders('t-1', ['a', 'b/x']);

      expect(controller.folderToggles('t-1').value,
          {'a': false, 'c': true, 'b/x': false});
    });

    test('opening the folders of files already open changes nothing', () {
      final controller = build();
      addTearDown(controller.dispose);
      controller.setFolderExpanded('t-1', 'a', expanded: true);

      controller.openFoldersOf('t-1', [_file('a/x.csv'), _file('b/y.csv')]);

      expect(controller.folderToggles('t-1').value, {'a': true},
          reason: 'b is open by default');
    });

    test('are kept per thread', () {
      final controller = build();
      addTearDown(controller.dispose);

      controller.setFolderExpanded('t-1', 'reports', expanded: false);

      expect(controller.folderToggles('t-2').value, isEmpty);
    });
  });

  group('fetchFileBytes', () {
    test("returns the bytes of the thread's file", () async {
      final bytes = Uint8List.fromList([9, 9, 9]);
      when(() => api.getThreadWorkdirFile('room-1', 't-1', 'dir/preview.png'))
          .thenAnswer((_) async => bytes);
      final controller = build();

      final out =
          await controller.fetchFileBytes('t-1', _file('dir/preview.png'));

      expect(out, bytes);
    });

    test('rethrows NotFoundException', () async {
      when(() => api.getThreadWorkdirFile(any(), any(), any())).thenThrow(
        const NotFoundException(message: 'gone', resource: '/x'),
      );
      final controller = build();

      await expectLater(
        controller.fetchFileBytes('t', _file('missing.png')),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('rethrows other errors', () async {
      when(() => api.getThreadWorkdirFile(any(), any(), any()))
          .thenThrow(const NetworkException(message: 'down'));
      final controller = build();

      await expectLater(
        controller.fetchFileBytes('t', _file('a.png')),
        throwsA(isA<NetworkException>()),
      );
    });
  });
}
