// Integration test — print is used for human-readable output.
// ignore_for_file: avoid_print, cast_nullable_to_non_nullable
@Tags(['integration'])
library;

import 'dart:io';

import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_monty_plugin/soliplex_monty_plugin.dart';
import 'package:test/test.dart';

/// End-to-end: ONE MontyScriptEnvironment with simplified tools.
final String _demoUrl =
    _getEnv('SOLIPLEX_DEMO_URL', 'https://demo.toughserv.com');
final String _localUrl =
    _getEnv('SOLIPLEX_LOCAL_URL', 'https://demo.toughserv.com');

String _getEnv(String key, String defaultValue) {
  try {
    return Platform.environment[key] ?? defaultValue;
  } on Object {
    return defaultValue;
  }
}

void main() {
  late MontyScriptEnvironment env;

  setUpAll(() {
    const ctx = SessionContext(serverId: 'test', roomId: 'test');
    final connections = {
      'demo': _buildConnection('demo', _demoUrl),
      'local': _buildConnection('local', _localUrl),
    };
    final soliplexTools = buildSoliplexTools(ctx, connections);

    env = MontyScriptEnvironment(
      tools: [
        ...soliplexTools,
        buildHelpTool(soliplexTools),
      ],
    );
  });

  tearDownAll(() async {
    env.dispose();
  });

  // ── Smoke Test ────────────────────────────────────────────────────

  test('smoke test: pure python math', () async {
    final r = await env.execute('1 + 1');
    if (r.error != null) print('Error: ${r.error}');
    expect(r.value.dartValue, 2);
  });

  test('smoke test: custom tool via closure', () async {
    final myTool = SoliplexTool(
      name: 'add_one',
      description: 'Adds one to n.',
      parameters: {
        'type': 'object',
        'properties': {
          'n': {'type': 'integer'},
        },
        'required': ['n'],
      },
      handler: (args) async => (args['n'] as int) + 1,
    );

    final localEnv = MontyScriptEnvironment(tools: [myTool]);
    final r = await localEnv.execute('add_one(n=10)');
    if (r.error != null) print('Error: ${r.error}');
    expect(r.value.dartValue, 11);
    localEnv.dispose();
  });

  // ── 1. Discovery ───────────────────────────────────────────────────

  test(
    '1. list_servers',
    () async {
      final r = await env.execute('soliplex_list_servers()');
      if (r.error != null) print('Error: ${r.error}');
      final servers = r.value.dartValue as List<dynamic>;
      print('  Servers: $servers');
      expect(
        servers.map((s) => (s as Map)['id']),
        containsAll(<String>['demo', 'local']),
      );
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  test(
    '2. list_rooms — demo',
    () async {
      final r = await env.execute('soliplex_list_rooms(server="demo")');
      if (r.error != null) print('Error: ${r.error}');
      final rooms = r.value.dartValue as List<dynamic>;
      print('  Demo rooms: $rooms');
      expect(rooms.isNotEmpty, isTrue);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  test(
    '4. get_room',
    () async {
      // Find first room ID
      final roomsRes = await env.execute('soliplex_list_rooms(server="demo")');
      final firstRoomId = ((roomsRes.value.dartValue as List).first
          as Map<String, dynamic>)['id'];

      final r = await env
          .execute('soliplex_get_room(server="demo", room_id="$firstRoomId")');
      if (r.error != null) print('Error: ${r.error}');
      final room = r.value.dartValue as Map;
      print('  Room: $room');
      expect(room['id'], firstRoomId);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  test(
    'help() works',
    () async {
      final r = await env.execute('help()');
      if (r.error != null) print('Error: ${r.error}');
      final data = r.value.dartValue as Map;
      expect(
        (data['tools'] as List).map((t) => (t as Map)['name']),
        contains('soliplex_new_thread'),
      );
      expect(
        (data['tools'] as List).map((t) => (t as Map)['name']),
        contains('help'),
      );
    },
  );
}

SoliplexConnection _buildConnection(String id, String baseUrl) {
  final transport = HttpTransport(client: DartHttpClient());
  final urlBuilder = UrlBuilder('$baseUrl/api/v1');

  return SoliplexConnection(
    serverId: id,
    alias: id,
    serverUrl: baseUrl,
    api: SoliplexApi(transport: transport, urlBuilder: urlBuilder),
    streamClient: AgUiStreamClient(
      httpTransport: transport,
      urlBuilder: urlBuilder,
    ),
  );
}
