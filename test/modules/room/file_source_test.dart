import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_frontend/src/modules/room/file_source.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

class _MockApi extends Mock implements SoliplexApi {}

WorkdirFile _workdirFile(String name) =>
    WorkdirFile(filename: name, url: Uri.parse('https://example.test/$name'));

FileUpload _upload(String name) =>
    FileUpload(filename: name, url: Uri.parse('https://example.test/$name'));

void main() {
  late _MockApi api;

  setUp(() {
    api = _MockApi();
  });

  group('FileSource', () {
    // Built at runtime, not const: identical const sources are one object, so
    // they would compare equal with no equality of their own.
    test('equal by kind and ids', () {
      String id(String s) => String.fromCharCodes(s.codeUnits);
      final sources = <FileSource Function()>[
        () => WorkspaceFileSource(roomId: id('r'), threadId: id('t')),
        () => ThreadUploadSource(roomId: id('r'), threadId: id('t')),
        () => RoomUploadSource(roomId: id('r')),
      ];
      for (final source in sources) {
        final a = source();
        final b = source();
        expect(a, isNot(same(b)));
        expect(a, b);
        expect(a.hashCode, b.hashCode);
      }
      expect(
        ThreadUploadSource(roomId: id('r'), threadId: id('t')),
        isNot(WorkspaceFileSource(roomId: id('r'), threadId: id('t'))),
      );
      expect(
        RoomUploadSource(roomId: id('r')),
        isNot(RoomUploadSource(roomId: id('r2'))),
      );
      // Equal across threads, one thread would fetch another's file.
      for (final source in <FileSource Function(String, String)>[
        (r, t) => ThreadUploadSource(roomId: r, threadId: t),
        (r, t) => WorkspaceFileSource(roomId: r, threadId: t),
      ]) {
        final base = source(id('r'), id('t'));
        expect(base, isNot(source(id('r'), id('t2'))));
        expect(base, isNot(source(id('r2'), id('t'))));
      }
    });
  });

  group('fetchFileBytes', () {
    test("fetches a workspace file from the thread's workspace", () async {
      final bytes = Uint8List.fromList([1]);
      when(() => api.getThreadWorkdirFile('room-1', 't-1', 'dir/a.png'))
          .thenAnswer((_) async => bytes);

      final out = await fetchFileBytes(
        api,
        const WorkspaceFileSource(roomId: 'room-1', threadId: 't-1'),
        _workdirFile('dir/a.png'),
      );

      expect(out, bytes);
    });

    test("fetches a room upload from the room's uploads", () async {
      final bytes = Uint8List.fromList([2]);
      when(() => api.getRoomUploadFile('room-1', 'a.pdf'))
          .thenAnswer((_) async => bytes);

      final out = await fetchFileBytes(
        api,
        const RoomUploadSource(roomId: 'room-1'),
        _upload('a.pdf'),
      );

      expect(out, bytes);
    });

    test("fetches a thread upload from the thread's uploads", () async {
      final bytes = Uint8List.fromList([3]);
      when(() => api.getThreadUploadFile('room-1', 't-1', 'a.pdf'))
          .thenAnswer((_) async => bytes);

      final out = await fetchFileBytes(
        api,
        const ThreadUploadSource(roomId: 'room-1', threadId: 't-1'),
        _upload('a.pdf'),
      );

      expect(out, bytes);
    });

    group('failures', () {
      late MemorySink sink;

      setUp(() {
        sink = MemorySink();
        LogManager.instance.addSink(sink);
        addTearDown(() => LogManager.instance.removeSink(sink));
      });

      test('rethrows NotFoundException without a warning', () async {
        when(() => api.getRoomUploadFile(any(), any())).thenThrow(
          const NotFoundException(message: 'gone', resource: '/x'),
        );

        await expectLater(
          fetchFileBytes(
            api,
            const RoomUploadSource(roomId: 'room-1'),
            _upload('a.pdf'),
          ),
          throwsA(isA<NotFoundException>()),
        );
        expect(sink.records.where((r) => r.level >= LogLevel.warning), isEmpty);
      });

      test('rethrows other errors, warning with the source and the file',
          () async {
        when(() => api.getThreadUploadFile(any(), any(), any()))
            .thenThrow(const NetworkException(message: 'down'));

        await expectLater(
          fetchFileBytes(
            api,
            const ThreadUploadSource(roomId: 'room-1', threadId: 't-1'),
            _upload('a.pdf'),
          ),
          throwsA(isA<NetworkException>()),
        );
        final record =
            sink.records.singleWhere((r) => r.level == LogLevel.warning);
        expect(record.error, isA<NetworkException>());
        expect(record.attributes['filename'], 'a.pdf');
        expect(record.attributes['source'], 'threadUploads');
        expect(record.attributes['roomId'], 'room-1');
        expect(record.attributes['threadId'], 't-1');
      });
    });
  });

  group('fileFetchFailureReason', () {
    for (final (error, reason) in <(Object, String)>[
      (
        const NotFoundException(message: 'No workdir file'),
        "File isn't available anymore",
      ),
      (const NetworkException(message: 'down'), "Couldn't reach the server"),
      (const AuthException(message: 'expired'), 'Sign in again'),
      (
        const PermissionDeniedException(message: 'denied'),
        "You don't have access to this file",
      ),
      (
        const ApiException(message: 'HTTP 500', statusCode: 500),
        'Server is temporarily unavailable',
      ),
      (
        const ApiException(message: 'HTTP 499', statusCode: 499),
        "The server couldn't send the file",
      ),
      (StateError('broken'), 'Something went wrong'),
    ]) {
      final status = error is ApiException ? ' ${error.statusCode}' : '';
      test('${error.runtimeType}$status reads "$reason"', () {
        expect(fileFetchFailureReason(error), reason);
      });
    }
  });
}
