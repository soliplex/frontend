// Integration test — print is used for human-readable output.
// ignore_for_file: avoid_print
@Tags(['integration'])
library;

import 'dart:io';

import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_monty_plugin/soliplex_monty_plugin.dart';
import 'package:test/test.dart';

/// Multi-server integration test.
///
/// Configure via environment variables:
///   SOLIPLEX_DEMO_URL  — cloud server base URL (e.g. https://demo.example.com)
///   SOLIPLEX_LOCAL_URL — local server base URL (default: http://localhost:8000)
///
/// Run with:
///   dart test test/integration/live_demo_test.dart -t integration --reporter expanded
final String _demoUrl =
    Platform.environment['SOLIPLEX_DEMO_URL'] ?? 'http://localhost:8000';
final String _localUrl =
    Platform.environment['SOLIPLEX_LOCAL_URL'] ?? 'http://localhost:8000';

void main() {
  late List<SoliplexTool> tools;
  late HttpTransport demoTransport;
  late HttpTransport localTransport;

  SoliplexConnection buildConnection(
    String serverId,
    String alias,
    String baseUrl,
  ) {
    final transport = HttpTransport(client: DartHttpClient());
    final urlBuilder = UrlBuilder('$baseUrl/api/v1');
    return SoliplexConnection(
      serverId: serverId,
      alias: alias,
      serverUrl: baseUrl,
      api: SoliplexApi(transport: transport, urlBuilder: urlBuilder),
      streamClient: AgUiStreamClient(
        httpTransport: transport,
        urlBuilder: urlBuilder,
      ),
    );
  }

  setUpAll(() {
    demoTransport = HttpTransport(client: DartHttpClient());
    localTransport = HttpTransport(client: DartHttpClient());

    final connections = {
      'demo': buildConnection('demo', 'demo', _demoUrl),
      'local': buildConnection('local', 'local', _localUrl),
    };
    tools = buildSoliplexTools(
      const SessionContext(serverId: 'demo', roomId: 'chat'),
      () => connections,
    );
  });

  tearDownAll(() {
    demoTransport.close();
    localTransport.close();
  });

  Future<Object?> call(String name, Map<String, Object?> args) {
    final tool = tools.firstWhere((t) => t.name == name);
    return tool.handler(args);
  }

  Map<String, dynamic> asMap(Object? r) => r! as Map<String, dynamic>;
  List<dynamic> asList(Object? r) => r! as List<dynamic>;

  // ── 1. list_servers — both servers visible ─────────────────────────

  test('1. list_servers shows both demo and local', () async {
    final result = asList(await call('soliplex_list_servers', {}));
    final ids =
        result.cast<Map<String, dynamic>>().map((e) => e['id']).toList();
    expect(ids, containsAll(['demo', 'local']));
    print('  ✓ Servers: ${ids.join(', ')}');
  });

  // ── 2. list_rooms — each server has different rooms ────────────────

  test('2. list_rooms from both servers', () async {
    final demoRooms =
        asList(await call('soliplex_list_rooms', {'server': 'demo'}));
    final localRooms =
        asList(await call('soliplex_list_rooms', {'server': 'local'}));

    final demoIds =
        demoRooms.cast<Map<String, dynamic>>().map((r) => r['id']).toList();
    final localIds =
        localRooms.cast<Map<String, dynamic>>().map((r) => r['id']).toList();

    print('  ✓ Demo rooms (${demoIds.length}): ${demoIds.join(', ')}');
    print('  ✓ Local rooms (${localIds.length}): ${localIds.join(', ')}');

    expect(demoRooms, isNotEmpty);
    expect(localRooms, isNotEmpty);
  });

  // ── 3. get_room — compare same concept across servers ──────────────

  test('3. get_room from each server', () async {
    final demoRoom = asMap(
      await call('soliplex_get_room', {
        'server': 'demo',
        'room_id': 'cooking',
      }),
    );
    print('  ✓ Demo "cooking": ${demoRoom['name']}');
    print('    Skills: ${demoRoom['skills']}');
    print('    Tools: ${demoRoom['tools']}');

    final localRoom = asMap(
      await call('soliplex_get_room', {
        'server': 'local',
        'room_id': 'chat',
      }),
    );
    print('  ✓ Local "chat": ${localRoom['name']}');
    print('    Skills: ${localRoom['skills']}');
    print('    Tools: ${localRoom['tools']}');
  });

  // ── 4. list_threads — both servers ─────────────────────────────────

  test('4. list_threads from both servers', () async {
    final demoThreads = asList(
      await call('soliplex_list_threads', {
        'server': 'demo',
        'room_id': 'cooking',
      }),
    );
    final localThreads = asList(
      await call('soliplex_list_threads', {
        'server': 'local',
        'room_id': 'chat',
      }),
    );
    print('  ✓ Demo cooking threads: ${demoThreads.length}');
    print('  ✓ Local chat threads: ${localThreads.length}');
  });

  // ── 5. new_thread on BOTH servers simultaneously ───────────────────

  test(
    '5. new_thread on demo AND local at the same time',
    () async {
      final results = await Future.wait([
        call('soliplex_new_thread', {
          'server': 'demo',
          'room_id': 'cooking',
          'message': 'One-sentence tip for making toast.',
        }),
        call('soliplex_new_thread', {
          'server': 'local',
          'room_id': 'chat',
          'message': 'What rooms are available on this server?',
        }),
      ]);

      final demoResult = asMap(results[0]);
      final localResult = asMap(results[1]);

      expect(demoResult['response'], isNotEmpty);
      expect(localResult['response'], isNotEmpty);

      print('  ✓ Demo response:');
      print('    ${_truncate(demoResult['response'] as String, 120)}');
      print('  ✓ Local response:');
      print('    ${_truncate(localResult['response'] as String, 120)}');
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  // ── 6. multi-turn on demo, single turn on local, interleaved ───────

  test(
    '6. interleaved conversation across servers',
    () async {
      final t1 = asMap(
        await call('soliplex_new_thread', {
          'server': 'demo',
          'room_id': 'cooking',
          'message': 'What is bruschetta?',
        }),
      );
      final demoThreadId = t1['thread_id'] as String;
      print('  ✓ Demo turn 1: ${_truncate(t1['response'] as String, 80)}');

      try {
        final local1 = asMap(
          await call('soliplex_new_thread', {
            'server': 'local',
            'room_id': 'chat',
            'message': 'Hello, what can you help with?',
          }),
        );
        print(
          '  ✓ Local turn 1: '
          '${_truncate(local1['response'] as String, 80)}',
        );
      } on SoliplexException catch (e) {
        print('  ⊘ Local interlude failed: $e');
      }

      final t2 = asMap(
        await call('soliplex_reply_thread', {
          'server': 'demo',
          'room_id': 'cooking',
          'thread_id': demoThreadId,
          'message': 'What bread works best for it?',
        }),
      );
      print('  ✓ Demo turn 2: ${_truncate(t2['response'] as String, 80)}');

      expect(t2['thread_id'], demoThreadId);
      expect(t2['response'], isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  // ── 7. get_documents — local server likely has RAG docs ────────────

  test('7. get_documents from local server', () async {
    try {
      final result = asList(
        await call('soliplex_get_documents', {
          'server': 'local',
          'room_id': 'chat',
        }),
      );
      print('  ✓ Local documents: ${result.length}');
      for (final doc in result.take(5)) {
        final d = doc as Map<String, dynamic>;
        print('    - ${d['title']} (${d['id']})');
      }
    } on SoliplexException catch (e) {
      print('  ⊘ Documents not available: $e');
    }
  });

  // ── 8. upload to local server ──────────────────────────────────────

  test('8. upload_file to local server', () async {
    try {
      final result = asMap(
        await call('soliplex_upload_file', {
          'server': 'local',
          'room_id': 'chat',
          'filename': 'integration-test.txt',
          'content': 'Hello from soliplex_monty_plugin integration test!',
        }),
      );
      print('  ✓ Uploaded: ${result['uploaded']}');
    } on SoliplexException catch (e) {
      print('  ⊘ Upload not available on local: $e');
    }
  });

  // ── 9. error: wrong server name ───────────────────────────────────

  test('9. error: unknown server', () {
    expect(
      () => call('soliplex_list_rooms', {'server': 'nope'}),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          allOf(contains('demo'), contains('local')),
        ),
      ),
    );
    print('  ✓ ArgumentError lists both: demo, local');
  });
}

String _truncate(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}...';
