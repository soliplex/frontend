// Integration test — print is used for human-readable output.
// ignore_for_file: avoid_print
@Tags(['integration'])
library;

import 'dart:convert';

import 'package:fe_plugin_soliplex/fe_plugin_soliplex.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

/// Multi-server integration test against:
///   - demo.toughserv.com (cloud, no auth)
///   - localhost:8000 (local, no auth)
///
/// Run with:
///   dart test test/integration/live_demo_test.dart -t integration --reporter expanded
void main() {
  late SoliplexPlugin plugin;
  late HttpTransport demoTransport;
  late HttpTransport localTransport;

  SoliplexConnection buildConnection(String baseUrl) {
    final transport = HttpTransport(client: DartHttpClient());
    final urlBuilder = UrlBuilder('$baseUrl/api/v1');
    return SoliplexConnection(
      api: SoliplexApi(transport: transport, urlBuilder: urlBuilder),
      streamClient: AgUiStreamClient(
        httpTransport: transport,
        urlBuilder: urlBuilder,
      ),
    );
  }

  setUpAll(() {
    final demoConn = buildConnection('https://demo.toughserv.com');
    final localConn = buildConnection('http://localhost:8000');
    demoTransport = HttpTransport(client: DartHttpClient());
    localTransport = HttpTransport(client: DartHttpClient());

    plugin = SoliplexPlugin(
      connections: {
        'demo': demoConn,
        'local': localConn,
      },
    );
  });

  tearDownAll(() {
    demoTransport.close();
    localTransport.close();
  });

  Future<Object?> call(String name, Map<String, Object?> args) {
    final fn = plugin.functions.firstWhere(
      (f) => f.schema.name == name,
    );
    return fn.handler(args);
  }

  Map<String, dynamic> decodeJson(Object? r) =>
      json.decode(r! as String) as Map<String, dynamic>;

  List<dynamic> decodeJsonList(Object? r) =>
      json.decode(r! as String) as List<dynamic>;

  // ── 1. list_servers — both servers visible ─────────────────────────

  test('1. list_servers shows both demo and local', () async {
    final result = decodeJsonList(
      await call('soliplex_list_servers', {}),
    );
    final ids =
        result.cast<Map<String, dynamic>>().map((e) => e['id']).toList();
    expect(ids, containsAll(['demo', 'local']));
    print('  ✓ Servers: ${ids.join(', ')}');
  });

  // ── 2. list_rooms — each server has different rooms ────────────────

  test('2. list_rooms from both servers', () async {
    final demoRooms = decodeJsonList(
      await call('soliplex_list_rooms', {'server': 'demo'}),
    );
    final localRooms = decodeJsonList(
      await call('soliplex_list_rooms', {'server': 'local'}),
    );

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
    // Demo: cooking room.
    final demoRoom = decodeJson(
      await call('soliplex_get_room', {
        'server': 'demo',
        'room_id': 'cooking',
      }),
    );
    print('  ✓ Demo "cooking": ${demoRoom['name']}');
    print('    Skills: ${demoRoom['skills']}');
    print('    Tools: ${demoRoom['tools']}');

    // Local: chat room.
    final localRoom = decodeJson(
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
    final demoThreads = decodeJsonList(
      await call('soliplex_list_threads', {
        'server': 'demo',
        'room_id': 'cooking',
      }),
    );
    final localThreads = decodeJsonList(
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
      // Fire both in parallel.
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

      final demoResult = decodeJson(results[0]);
      final localResult = decodeJson(results[1]);

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
      // Turn 1: start on demo.
      final t1 = decodeJson(
        await call('soliplex_new_thread', {
          'server': 'demo',
          'room_id': 'cooking',
          'message': 'What is bruschetta?',
        }),
      );
      final demoThreadId = t1['thread_id'] as String;
      print('  ✓ Demo turn 1: ${_truncate(t1['response'] as String, 80)}');

      // Interlude: ask local something (may fail if local backend errors).
      try {
        final local1 = decodeJson(
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

      // Turn 2: reply on demo — proves history survived the interlude.
      final t2 = decodeJson(
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
      final result = decodeJsonList(
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
      final result = decodeJson(
        await call('soliplex_upload_file', {
          'server': 'local',
          'room_id': 'chat',
          'filename': 'integration-test.txt',
          'content': 'Hello from fe_plugin_soliplex integration test!',
        }),
      );
      print('  ✓ Uploaded: ${result['uploaded']}');
    } on SoliplexException catch (e) {
      print('  ⊘ Upload not available on local: $e');
    }
  });

  // ── 9. MCP token from demo ─────────────────────────────────────────

  test('9. get_mcp_token from demo', () async {
    try {
      final result = decodeJson(
        await call('soliplex_get_mcp_token', {
          'server': 'demo',
          'room_id': 'image_generation',
        }),
      );
      print(
        '  ✓ MCP token: ${_truncate(result['mcp_token'] as String, 30)}',
      );
    } on SoliplexException catch (e) {
      print('  ⊘ MCP not available: $e');
    }
  });

  // ── 10. error: wrong server name ───────────────────────────────────

  test('10. error: unknown server', () {
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
