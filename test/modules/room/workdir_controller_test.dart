import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'package:soliplex_frontend/src/modules/room/ui/workdir_files.dart'
    show DownloadOutcome;
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

  WorkdirController build({
    SaveFile? saveFile,
    bool isWeb = false,
  }) {
    return WorkdirController(
      api: api,
      roomId: 'room-1',
      saveFile: saveFile ??
          ({required String fileName, required Uint8List bytes}) async {
            return '/tmp/$fileName';
          },
      isWeb: isWeb,
    );
  }

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

  group('downloadFile', () {
    test('returns success on native when saveFile returns a path', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      when(() => api.getThreadWorkdirFile(any(), any(), any()))
          .thenAnswer((_) async => bytes);

      String? gotName;
      Uint8List? gotBytes;
      final controller = build(
        saveFile: ({required String fileName, required Uint8List bytes}) async {
          gotName = fileName;
          gotBytes = bytes;
          return '/Users/me/Desktop/$fileName';
        },
      );

      final outcome = await controller.downloadFile('t', _file('output.csv'));

      expect(outcome, DownloadOutcome.success);
      expect(gotName, 'output.csv');
      expect(gotBytes, bytes);
    });

    test('fetches a nested file by its path and saves it under its basename',
        () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      when(() => api.getThreadWorkdirFile('room-1', 't', 'dir/sub/file.csv'))
          .thenAnswer((_) async => bytes);

      String? gotName;
      final controller = build(
        saveFile: ({required String fileName, required Uint8List bytes}) async {
          gotName = fileName;
          return '/Users/me/Desktop/$fileName';
        },
      );

      final outcome =
          await controller.downloadFile('t', _file('dir/sub/file.csv'));

      expect(outcome, DownloadOutcome.success);
      expect(gotName, 'file.csv');
    });

    test('returns cancelled on native when saveFile returns null', () async {
      when(() => api.getThreadWorkdirFile(any(), any(), any()))
          .thenAnswer((_) async => Uint8List(0));
      final controller = build(
        saveFile: ({required String fileName, required Uint8List bytes}) async {
          return null;
        },
      );

      expect(
        await controller.downloadFile('t', _file('output.csv')),
        DownloadOutcome.cancelled,
      );
    });

    test('returns success on web even when saveFile returns null', () async {
      when(() => api.getThreadWorkdirFile(any(), any(), any()))
          .thenAnswer((_) async => Uint8List(0));
      final controller = build(
        isWeb: true,
        saveFile: ({required String fileName, required Uint8List bytes}) async {
          return null;
        },
      );

      expect(
        await controller.downloadFile('t', _file('output.csv')),
        DownloadOutcome.success,
      );
    });

    test('returns failed when the API throws', () async {
      when(() => api.getThreadWorkdirFile(any(), any(), any()))
          .thenThrow(const NetworkException(message: 'down'));
      final controller = build();

      expect(
        await controller.downloadFile('t', _file('output.csv')),
        DownloadOutcome.failed,
      );
    });

    test('returns failed when saveFile throws', () async {
      when(() => api.getThreadWorkdirFile(any(), any(), any()))
          .thenAnswer((_) async => Uint8List(0));
      final controller = build(
        saveFile: ({required String fileName, required Uint8List bytes}) async {
          throw Exception('disk full');
        },
      );

      expect(
        await controller.downloadFile('t', _file('output.csv')),
        DownloadOutcome.failed,
      );
    });

    group('logs', () {
      late MemorySink sink;

      setUp(() {
        sink = MemorySink();
        LogManager.instance.addSink(sink);
        addTearDown(() => LogManager.instance.removeSink(sink));
      });

      LogRecord warning() =>
          sink.records.singleWhere((r) => r.level == LogLevel.warning);

      test('a failed fetch as a warning with the failure and its status code',
          () async {
        when(() => api.getThreadWorkdirFile(any(), any(), any())).thenThrow(
          const ApiException(
            message: 'HTTP 500: workspace unreadable',
            statusCode: 500,
          ),
        );
        final controller = build();

        await controller.downloadFile('t', _file('dir/output.csv'));

        final record = warning();
        expect(
          record.error,
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 500),
        );
        expect(record.attributes['filename'], 'dir/output.csv');
      });

      test("a vanished file as a warning, unlike a preview's debug-level 404",
          () async {
        when(() => api.getThreadWorkdirFile(any(), any(), any()))
            .thenThrow(const NotFoundException(message: 'No workdir file'));
        final controller = build();

        await controller.downloadFile('t', _file('dir/output.csv'));

        expect(warning().error, isA<NotFoundException>());
      });

      test('a failed save as a warning without the failure text', () async {
        when(() => api.getThreadWorkdirFile(any(), any(), any()))
            .thenAnswer((_) async => Uint8List(1));
        final controller = build(
          saveFile: ({required String fileName, required Uint8List bytes}) {
            throw Exception('cannot write /Users/me/Desktop/output.csv');
          },
        );

        await controller.downloadFile('t', _file('dir/output.csv'));

        final record = warning();
        expect(record.error, isNull);
        expect(record.attributes['failure'], '_Exception');
        expect(record.toString(), isNot(contains('/Users/me')));
        expect(record.attributes['filename'], 'dir/output.csv');
      });
    });
  });

  group('fetchFileBytes', () {
    test('returns API bytes and skips the save dialog', () async {
      final bytes = Uint8List.fromList([9, 9, 9]);
      when(() => api.getThreadWorkdirFile(any(), any(), any()))
          .thenAnswer((_) async => bytes);

      var saveCalls = 0;
      final controller = build(
        saveFile: ({required String fileName, required Uint8List bytes}) async {
          saveCalls++;
          return '/tmp/$fileName';
        },
      );

      final out = await controller.fetchFileBytes('t-1', _file('preview.png'));

      expect(out, bytes);
      expect(saveCalls, 0);
      verify(() => api.getThreadWorkdirFile('room-1', 't-1', 'preview.png'))
          .called(1);
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
