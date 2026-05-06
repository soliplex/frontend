import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_client/soliplex_client.dart';

import 'package:soliplex_frontend/src/modules/room/ui/workdir_files_section.dart'
    show DownloadOutcome;
import 'package:soliplex_frontend/src/modules/room/workdir_controller.dart';

class _MockApi extends Mock implements SoliplexApi {}

WorkdirFile _file(String name) =>
    WorkdirFile(filename: name, url: Uri.parse('https://example.test/$name'));

void main() {
  late _MockApi api;

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

  group('fetchFiles', () {
    test('returns the API list and caches the future per (thread, run)',
        () async {
      var calls = 0;
      when(() => api.getRunWorkdirFiles(any(), any(), any()))
          .thenAnswer((_) async {
        calls++;
        return [_file('a.txt')];
      });
      final controller = build();

      final first = await controller.fetchFiles('t-1', 'r-1');
      final second = await controller.fetchFiles('t-1', 'r-1');

      expect(first, hasLength(1));
      expect(second, same(first));
      expect(calls, 1);
    });

    test('returns const [] on NotFoundException', () async {
      when(() => api.getRunWorkdirFiles(any(), any(), any())).thenThrow(
        const NotFoundException(message: 'no sandbox', resource: '/x'),
      );
      final controller = build();

      expect(await controller.fetchFiles('t-1', 'r-1'), isEmpty);
    });

    test('rethrows and evicts on non-404 error so retry re-fetches', () async {
      var calls = 0;
      when(() => api.getRunWorkdirFiles(any(), any(), any()))
          .thenAnswer((_) async {
        calls++;
        if (calls == 1) {
          throw const NetworkException(message: 'down');
        }
        return [_file('after-retry.txt')];
      });
      final controller = build();

      await expectLater(
        controller.fetchFiles('t-1', 'r-1'),
        throwsA(isA<NetworkException>()),
      );

      final retried = await controller.fetchFiles('t-1', 'r-1');
      expect(retried.single.filename, 'after-retry.txt');
      expect(calls, 2);
    });

    test('does not collide across threads sharing a runId', () async {
      when(() => api.getRunWorkdirFiles('room-1', 't-A', 'r-shared'))
          .thenAnswer((_) async => [_file('a.txt')]);
      when(() => api.getRunWorkdirFiles('room-1', 't-B', 'r-shared'))
          .thenAnswer((_) async => [_file('b.txt')]);
      final controller = build();

      final a = await controller.fetchFiles('t-A', 'r-shared');
      final b = await controller.fetchFiles('t-B', 'r-shared');

      expect(a.single.filename, 'a.txt');
      expect(b.single.filename, 'b.txt');
    });

    test('clearCache forces a re-fetch on next call', () async {
      var calls = 0;
      when(() => api.getRunWorkdirFiles(any(), any(), any()))
          .thenAnswer((_) async {
        calls++;
        return const [];
      });
      final controller = build();

      await controller.fetchFiles('t', 'r');
      controller.clearCache();
      await controller.fetchFiles('t', 'r');

      expect(calls, 2);
    });
  });

  group('download', () {
    test('returns success on native when saveFile returns a path', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      when(() => api.getRunWorkdirFile(any(), any(), any(), any()))
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

      final outcome = await controller.download('t', 'r', _file('output.csv'));

      expect(outcome, DownloadOutcome.success);
      expect(gotName, 'output.csv');
      expect(gotBytes, bytes);
    });

    test('returns cancelled on native when saveFile returns null', () async {
      when(() => api.getRunWorkdirFile(any(), any(), any(), any()))
          .thenAnswer((_) async => Uint8List(0));
      final controller = build(
        saveFile: ({required String fileName, required Uint8List bytes}) async {
          return null;
        },
      );

      expect(
        await controller.download('t', 'r', _file('output.csv')),
        DownloadOutcome.cancelled,
      );
    });

    test('returns success on web even when saveFile returns null', () async {
      when(() => api.getRunWorkdirFile(any(), any(), any(), any()))
          .thenAnswer((_) async => Uint8List(0));
      final controller = build(
        isWeb: true,
        saveFile: ({required String fileName, required Uint8List bytes}) async {
          return null;
        },
      );

      expect(
        await controller.download('t', 'r', _file('output.csv')),
        DownloadOutcome.success,
      );
    });

    test('returns failed when the API throws', () async {
      when(() => api.getRunWorkdirFile(any(), any(), any(), any()))
          .thenThrow(const NetworkException(message: 'down'));
      final controller = build();

      expect(
        await controller.download('t', 'r', _file('output.csv')),
        DownloadOutcome.failed,
      );
    });

    test('returns failed when saveFile throws', () async {
      when(() => api.getRunWorkdirFile(any(), any(), any(), any()))
          .thenAnswer((_) async => Uint8List(0));
      final controller = build(
        saveFile: ({required String fileName, required Uint8List bytes}) async {
          throw Exception('disk full');
        },
      );

      expect(
        await controller.download('t', 'r', _file('output.csv')),
        DownloadOutcome.failed,
      );
    });
  });
}
