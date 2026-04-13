// Integration test — print is used for human-readable output.
// ignore_for_file: avoid_print, cast_nullable_to_non_nullable
@Tags(['integration'])
library;

import 'dart:io';

import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_monty_plugin/soliplex_monty_plugin.dart';
import 'package:test/test.dart';

/// End-to-end: ONE long-lived AgentSession + SoliplexPlugin.
/// Python calls host functions → live SSE streaming → multi-turn conversations.
///
/// Uses a SINGLE session for ALL tests (no create/dispose per test).
///
/// Configure via environment variables:
///   SOLIPLEX_DEMO_URL  — cloud server base URL
///   SOLIPLEX_LOCAL_URL — local server base URL (default: http://localhost:8000)
///
/// Run with:
///   cd packages/soliplex_monty_plugin
///   dart test test/integration/agent_session_test.dart -t integration --reporter expanded
final String _demoUrl =
    Platform.environment['SOLIPLEX_DEMO_URL'] ?? 'http://localhost:8000';
final String _localUrl =
    Platform.environment['SOLIPLEX_LOCAL_URL'] ?? 'http://localhost:8000';

void main() {
  late AgentSession session;

  setUpAll(() {
    session = AgentSession(
      plugins: [
        SoliplexPlugin(
          connections: {
            'demo': _buildConnection(_demoUrl),
            'local': _buildConnection(_localUrl),
          },
        ),
      ],
    );
  });

  tearDownAll(() async {
    await session.dispose();
  });

  // ── 1. Discovery ───────────────────────────────────────────────────

  test(
    '1. list_servers',
    () async {
      final r = await session.execute('''
import json
json.loads(soliplex_list_servers())
''');
      final servers = r.value?.dartValue as List<dynamic>;
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
      final r = await session.execute('''
import json
rooms = json.loads(soliplex_list_rooms("demo"))
[r["id"] for r in rooms]
''');
      print('  Demo rooms: ${r.value?.dartValue}');
      expect(r.value?.dartValue, contains('cooking'));
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  test(
    '3. list_rooms — local',
    () async {
      final r = await session.execute('''
import json
rooms = json.loads(soliplex_list_rooms("local"))
[r["id"] for r in rooms]
''');
      print('  Local rooms: ${r.value?.dartValue}');
      expect(r.value?.dartValue, contains('bwrap_sandbox'));
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  test(
    '4. get_room',
    () async {
      final r = await session.execute('''
import json
room = json.loads(soliplex_get_room("demo", "cooking"))
room["name"]
''');
      print('  Room: ${r.value?.dartValue}');
      expect(r.value?.dartValue, 'Cooking Coach');
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  // ── 2. SSE conversation — single turn ──────────────────────────────

  test(
    '5. new_thread on demo — SSE works',
    () async {
      final r = await session.execute('''
import json
data = json.loads(
    soliplex_new_thread("demo", "cooking", "One tip for crispy bacon.")
)
data["response"]
''');
      final response = r.value?.dartValue as String;
      print('  Response: ${_trunc(response, 120)}');
      expect(response, isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  // ── 3. Multi-turn — state persists across execute() calls ──────────

  test(
    '6. multi-turn: new_thread',
    () async {
      final r = await session.execute('''
import json
data = json.loads(
    soliplex_new_thread("demo", "cooking", "What is bruschetta?")
)
thread_id = data["thread_id"]
turn1 = data["response"]
turn1
''');
      print('  Turn 1: ${_trunc(r.value?.dartValue as String, 100)}');
      expect(r.value?.dartValue, isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    '7. multi-turn: reply_thread (uses persisted thread_id)',
    () async {
      final r = await session.execute('''
import json
data = json.loads(
    soliplex_reply_thread("demo", "cooking", thread_id, "What bread works best?")
)
turn2 = data["response"]
turn2
''');
      print('  Turn 2: ${_trunc(r.value?.dartValue as String, 100)}');
      expect(r.value?.dartValue, isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    '8. multi-turn: second reply (3-turn conversation)',
    () async {
      final r = await session.execute('''
import json
data = json.loads(
    soliplex_reply_thread("demo", "cooking", thread_id, "How long do I toast it?")
)
turn3 = data["response"]
turn3
''');
      print('  Turn 3: ${_trunc(r.value?.dartValue as String, 100)}');
      expect(r.value?.dartValue, isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  // ── 4. Uploads ─────────────────────────────────────────────────────

  test(
    '9. upload_file to room',
    () async {
      final r = await session.execute('''
import json
result = json.loads(
    soliplex_upload_file("local", "bwrap_sandbox", "agent-test.txt", "Hello from AgentSession!")
)
result
''');
      final result = r.value?.dartValue as Map?;
      if (result != null && result.containsKey('uploaded')) {
        print('  Uploaded: ${result['uploaded']} to ${result['room_id']}');
        expect(result['uploaded'], 'agent-test.txt');
      } else {
        print('  Upload not available: ${r.value?.dartValue ?? r.error}');
      }
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  test(
    '10a. create local thread for upload',
    () async {
      final r = await session.execute('''
import json
t = json.loads(soliplex_new_thread("local", "chat", "Hello"))
local_tid = t["thread_id"]
local_tid
''');
      print('  Local thread: ${r.value?.dartValue}');
      expect(r.value?.dartValue, isA<String>());
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    '10b. upload_to_thread',
    () async {
      final r = await session.execute('''
import json
result = json.loads(
    soliplex_upload_to_thread("local", "chat", local_tid, "thread-notes.txt", "Notes from agent")
)
result
''');
      final result = r.value?.dartValue as Map?;
      if (result != null && result.containsKey('uploaded')) {
        print(
          '  Uploaded: ${result['uploaded']} '
          'to thread ${result['thread_id']}',
        );
        expect(result['uploaded'], 'thread-notes.txt');
      } else {
        print('  Upload not available: ${r.value?.dartValue ?? r.error}');
      }
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  // ── 5. Cross-server ────────────────────────────────────────────────

  test(
    '11. new_thread on local',
    () async {
      final r = await session.execute('''
import json
data = json.loads(
    soliplex_new_thread("local", "chat", "Hello, what can you do?")
)
data["response"]
''');
      print('  Local: ${_trunc(r.value?.dartValue as String, 100)}');
      expect(r.value?.dartValue, isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  // ── 5. bwrap generates monty code, we execute it ───────────────────

  test(
    '12. bwrap codegen → extract → execute',
    () async {
      // Step 1: Ask bwrap to generate code
      final gen = await session.execute('''
import json
prompt = """Write a Python program using these host functions:
  soliplex_list_servers() -> JSON string of server dicts
  soliplex_list_rooms(server) -> JSON string of room dicts

The program should list all servers, then list rooms for the first server.
Return a dict with server_id and room_ids.
Return ONLY code in a ```monty``` block."""

data = json.loads(
    soliplex_new_thread("local", "bwrap_sandbox", prompt)
)
generated = data["response"]
generated
''');
      final generated = gen.value?.dartValue as String;
      print('  Generated:');
      print('  ${_trunc(generated, 200)}');

      // Step 2: Extract code block
      final extracted = await session.execute(r'''
import re
pattern = r"```(?:monty|python)\n(.*?)```"
match = re.search(pattern, generated, re.DOTALL)
code = match.group(1) if match else None
code
''');
      final code = extracted.value?.dartValue;
      if (code == null) {
        print('  No code block found — skipping execution');

        return;
      }
      print('  Extracted code:');
      print('  ${_trunc(code as String, 200)}');

      // Step 3: Execute the generated code
      final result = await session.execute(code);
      print('  Result: ${result.value?.dartValue}');
      expect(result.value?.dartValue, isNotNull);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}

SoliplexConnection _buildConnection(String baseUrl) {
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

String _trunc(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}...';
