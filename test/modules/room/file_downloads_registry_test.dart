import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_frontend/src/modules/auth/admin_status.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';
import 'package:soliplex_frontend/src/modules/room/file_downloads.dart';
import 'package:soliplex_frontend/src/modules/room/file_downloads_registry.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../helpers/fakes.dart' show FakeTokenRefreshService;
import '../../helpers/test_server_entry.dart' show testAccessToken;

class _FakeHttpClient extends Fake implements SoliplexHttpClient {}

class _FakeServerConnection extends Fake implements ServerConnection {
  _FakeServerConnection(this.api);

  @override
  final SoliplexApi api;
}

class _MockApi extends Mock implements SoliplexApi {}

ServerEntry _entry(String serverId, SoliplexApi api) => ServerEntry(
      serverId: serverId,
      alias: serverId,
      serverUrl: Uri.parse('https://$serverId.example.com'),
      auth: AuthSession(refreshService: FakeTokenRefreshService()),
      httpClient: _FakeHttpClient(),
      connection: _FakeServerConnection(api),
      adminStatus: AdminStatus(api: api, serverId: serverId),
    );

WorkdirFile _file(String name) =>
    WorkdirFile(filename: name, url: Uri.parse('https://example.test/$name'));

Future<String?> _saveToTmp({
  required String fileName,
  required Uint8List bytes,
}) async =>
    '/tmp/$fileName';

void main() {
  late _MockApi api;

  setUp(() {
    api = _MockApi();
  });

  group('downloadWorkdirFile', () {
    Future<DownloadOutcome> download(
      WorkdirFile file, {
      SaveFile saveFile = _saveToTmp,
      bool isWeb = false,
      bool isUnwanted = false,
    }) =>
        downloadWorkdirFile(
          api: api,
          roomId: 'room-1',
          threadId: 't',
          file: file,
          saveFile: saveFile,
          isWeb: isWeb,
          isUnwanted: () => isUnwanted,
        );

    test('returns success on native when saveFile returns a path', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      when(() => api.getThreadWorkdirFile(any(), any(), any()))
          .thenAnswer((_) async => bytes);

      String? gotName;
      Uint8List? gotBytes;
      final outcome = await download(
        _file('output.csv'),
        saveFile: ({required String fileName, required Uint8List bytes}) async {
          gotName = fileName;
          gotBytes = bytes;
          return '/Users/me/Desktop/$fileName';
        },
      );

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
      final outcome = await download(
        _file('dir/sub/file.csv'),
        saveFile: ({required String fileName, required Uint8List bytes}) async {
          gotName = fileName;
          return '/Users/me/Desktop/$fileName';
        },
      );

      expect(outcome, DownloadOutcome.success);
      expect(gotName, 'file.csv');
    });

    test('returns cancelled on native when saveFile returns null', () async {
      when(() => api.getThreadWorkdirFile(any(), any(), any()))
          .thenAnswer((_) async => Uint8List(0));

      expect(
        await download(
          _file('output.csv'),
          saveFile: ({required String fileName, required Uint8List bytes}) =>
              Future.value(),
        ),
        DownloadOutcome.cancelled,
      );
    });

    test('returns success on web even when saveFile returns null', () async {
      when(() => api.getThreadWorkdirFile(any(), any(), any()))
          .thenAnswer((_) async => Uint8List(0));

      expect(
        await download(
          _file('output.csv'),
          isWeb: true,
          saveFile: ({required String fileName, required Uint8List bytes}) =>
              Future.value(),
        ),
        DownloadOutcome.success,
      );
    });

    test('returns failed when the API throws', () async {
      when(() => api.getThreadWorkdirFile(any(), any(), any()))
          .thenThrow(const NetworkException(message: 'down'));

      expect(await download(_file('output.csv')), DownloadOutcome.failed);
    });

    test('returns failed when saveFile throws', () async {
      when(() => api.getThreadWorkdirFile(any(), any(), any()))
          .thenAnswer((_) async => Uint8List(0));

      expect(
        await download(
          _file('output.csv'),
          saveFile: ({required String fileName, required Uint8List bytes}) =>
              throw Exception('disk full'),
        ),
        DownloadOutcome.failed,
      );
    });

    test('opens no save dialog once nobody wants the file', () async {
      when(() => api.getThreadWorkdirFile(any(), any(), any()))
          .thenAnswer((_) async => Uint8List(1));
      final saved = <String>[];

      final outcome = await download(
        _file('output.csv'),
        isUnwanted: true,
        saveFile: ({required String fileName, required Uint8List bytes}) async {
          saved.add(fileName);
          return '/tmp/$fileName';
        },
      );

      expect(outcome, DownloadOutcome.cancelled);
      expect(saved, isEmpty);
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

        await download(_file('dir/output.csv'));

        final record = warning();
        expect(
          record.error,
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 500),
        );
        expect(record.attributes['filename'], 'dir/output.csv');
        expect(record.message, contains('roomId=room-1'));
      });

      test("a vanished file as a warning, unlike a preview's debug-level 404",
          () async {
        when(() => api.getThreadWorkdirFile(any(), any(), any()))
            .thenThrow(const NotFoundException(message: 'No workdir file'));

        await download(_file('dir/output.csv'));

        expect(warning().error, isA<NotFoundException>());
      });

      test('a failed save as a warning with what failed and where', () async {
        when(() => api.getThreadWorkdirFile(any(), any(), any()))
            .thenAnswer((_) async => Uint8List(1));
        final failure = Exception('cannot write /Users/me/Desktop/output.csv');

        await download(
          _file('dir/output.csv'),
          saveFile: ({required String fileName, required Uint8List bytes}) {
            throw failure;
          },
        );

        final record = warning();
        // The local path says where the save failed; it is not a secret.
        expect(record.error, failure);
        expect(record.attributes['filename'], 'dir/output.csv');
      });

      test(
          'a fetch failing once nobody wants the file as a drop, not a '
          'failure', () async {
        when(() => api.getThreadWorkdirFile(any(), any(), any()))
            .thenThrow(const NetworkException(message: 'connection closed'));

        final outcome = await download(_file('output.csv'), isUnwanted: true);

        expect(outcome, DownloadOutcome.cancelled);
        expect(sink.records.where((r) => r.level >= LogLevel.warning), isEmpty);
      });

      test('a download dropped once unwanted, at debug', () async {
        final level = LogManager.instance.minimumLevel;
        LogManager.instance.minimumLevel = LogLevel.debug;
        addTearDown(() => LogManager.instance.minimumLevel = level);
        when(() => api.getThreadWorkdirFile(any(), any(), any()))
            .thenAnswer((_) async => Uint8List(1));

        await download(_file('dir/output.csv'), isUnwanted: true);

        expect(
          sink.records.map((r) => r.message),
          contains(startsWith('workdir download dropped')),
        );
      });
    });
  });

  group('FileDownloadsRegistry', () {
    late Signal<Map<String, ServerEntry>> servers;
    late ServerEntry entry;
    late List<String> saved;
    late FileDownloadsRegistry registry;

    setUp(() {
      entry = _entry('srv-1', api);
      servers = Signal({'srv-1': entry});
      saved = [];
      registry = FileDownloadsRegistry(
        servers: servers,
        saveFile: ({required String fileName, required Uint8List bytes}) async {
          saved.add(fileName);
          return '/tmp/$fileName';
        },
        isWeb: false,
      );
    });

    tearDown(() {
      registry.dispose();
      servers.dispose();
    });

    FileDownloads downloads(
            {String roomId = 'room-1', String thread = 't-1'}) =>
        registry.downloadsFor(entry: entry, roomId: roomId, threadId: thread);

    test("keeps a thread's downloads, apart from other threads' and rooms'",
        () {
      expect(downloads(), same(downloads()));
      expect(downloads(thread: 't-2'), isNot(same(downloads())));
      expect(downloads(roomId: 'room-2'), isNot(same(downloads())));
    });

    test("a thread's download saves the file from that thread", () async {
      when(() => api.getThreadWorkdirFile('room-1', 't-2', 'out/report.csv'))
          .thenAnswer((_) async => Uint8List.fromList([1]));
      final file = _file('out/report.csv');

      await downloads(thread: 't-2').start(file);

      expect(
        downloads(thread: 't-2').stateOf(file),
        DownloadFeedbackState.success,
      );
      expect(saved, ['report.csv']);
    });

    void expectClearedMidDownload(void Function() clear) {
      fakeAsync((async) {
        final fetch = Completer<Uint8List>();
        when(() => api.getThreadWorkdirFile(any(), any(), any()))
            .thenAnswer((_) => fetch.future);
        unawaited(downloads().start(_file('output.csv')));

        clear();
        fetch.complete(Uint8List.fromList([1]));
        async.flushMicrotasks();

        expect(saved, isEmpty, reason: 'nobody there asked for the file');
        expect(async.pendingTimers, isEmpty);
      });
    }

    test('on the web, a download handed to the browser shows as saved',
        () async {
      when(() => api.getThreadWorkdirFile(any(), any(), any()))
          .thenAnswer((_) async => Uint8List.fromList([1]));
      final web = FileDownloadsRegistry(
        servers: servers,
        saveFile: ({required String fileName, required Uint8List bytes}) =>
            Future.value(),
        isWeb: true,
      );
      addTearDown(web.dispose);
      final downloads =
          web.downloadsFor(entry: entry, roomId: 'room-1', threadId: 't-1');

      await downloads.start(_file('output.csv'));

      expect(
        downloads.stateOf(_file('output.csv')),
        DownloadFeedbackState.success,
      );
    });

    void signIn() => entry.auth.login(
          provider: const OidcProvider(
            discoveryUrl: 'https://auth.example.com/.well-known/openid',
            clientId: 'test-client',
          ),
          tokens: AuthTokens(
            accessToken: testAccessToken(),
            refreshToken: 'refresh',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );

    test('signing out while a download fetches saves nothing', () async {
      signIn();
      final fetch = Completer<Uint8List>();
      when(() => api.getThreadWorkdirFile(any(), any(), any()))
          .thenAnswer((_) => fetch.future);
      final download = downloads().start(_file('output.csv'));

      entry.auth.logout();
      fetch.complete(Uint8List.fromList([1]));
      await download;

      expect(saved, isEmpty);
      expect(
        downloads().stateOf(_file('output.csv')),
        DownloadFeedbackState.idle,
      );
    });

    test('signing out and back in while a download fetches saves nothing',
        () async {
      signIn();
      final fetch = Completer<Uint8List>();
      when(() => api.getThreadWorkdirFile(any(), any(), any()))
          .thenAnswer((_) => fetch.future);
      final download = downloads().start(_file('output.csv'));

      entry.auth.logout();
      signIn();
      fetch.complete(Uint8List.fromList([1]));
      await download;

      expect(saved, isEmpty, reason: 'signing out ended it');
    });

    test('a server never signed in, as with no auth, still saves', () async {
      when(() => api.getThreadWorkdirFile(any(), any(), any()))
          .thenAnswer((_) async => Uint8List.fromList([1]));

      await downloads().start(_file('output.csv'));

      expect(saved, ['output.csv']);
    });

    test(
        "removing a server clears its downloads, and saves nothing they'd "
        'started', () {
      expectClearedMidDownload(() => servers.value = {});
    });

    test("evicting a server, as a user switch does, clears its downloads", () {
      expectClearedMidDownload(() => registry.evictServer('srv-1'));
    });
  });
}
