// Integration test — print is used for human-readable output.
// ignore_for_file: avoid_print, cast_nullable_to_non_nullable
@Tags(['integration'])
library;

import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:fe_plugin_soliplex/fe_plugin_soliplex.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

/// End-to-end: AgentSession (sandbox mode) + SoliplexPlugin + bwrap_sandbox.
///
/// Uses `sandbox: true` — fresh FFI interpreter per execute() call.
/// No SEGFAULT on sequential SSE-streaming host function calls.
///
/// Run with:
///   cd packages/fe_plugin_soliplex
///   dart test test/integration/agent_session_test.dart -t integration --reporter expanded
void main() {
  late AgentSession session;

  setUpAll(() {
    session = AgentSession(
      sandbox: true,
      plugins: [
        SoliplexPlugin(
          connections: {
            'demo': _buildConnection('https://demo.toughserv.com'),
            'local': _buildConnection('http://localhost:8000'),
          },
        ),
      ],
    );
  });

  tearDownAll(() async {
    await session.dispose();
  });

  // ── 1. Basic host function calls ───────────────────────────────────

  test(
    '1. list_servers — both servers visible',
    () async {
      final result = await session.execute('''
import json
servers = json.loads(soliplex_list_servers())
[s["id"] for s in servers]
''');
      print('  Servers: ${result.value?.dartValue}');
      expect(result.value?.dartValue, containsAll(<String>['demo', 'local']));
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  test(
    '2. list_rooms — both servers',
    () async {
      final result = await session.execute('''
import json
demo = json.loads(soliplex_list_rooms("demo"))
demo_ids = [r["id"] for r in demo]
demo_ids
''');
      print('  Demo: ${result.value?.dartValue}');
      expect(result.value?.dartValue, contains('cooking'));

      final result2 = await session.execute('''
import json
local = json.loads(soliplex_list_rooms("local"))
local_ids = [r["id"] for r in local]
local_ids
''');
      print('  Local: ${result2.value?.dartValue}');
      expect(result2.value?.dartValue, contains('bwrap_sandbox'));
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  test(
    '3. get_room — demo cooking',
    () async {
      final result = await session.execute('''
import json
room = json.loads(soliplex_get_room("demo", "cooking"))
room["name"]
''');
      print('  Room: ${result.value?.dartValue}');
      expect(result.value?.dartValue, 'Cooking Coach');
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  // ── 2. SSE streaming — single turn ─────────────────────────────────

  test(
    '4. new_thread on demo — SSE streaming works',
    () async {
      final result = await session.execute('''
import json
data = json.loads(
    soliplex_new_thread("demo", "cooking", "One tip for crispy bacon.")
)
response = data["response"]
response
''');
      final response = result.value?.dartValue as String;
      print('  Response: ${_trunc(response, 150)}');
      expect(response, isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  // ── 3. SSE streaming — multi-turn (sandbox mode prevents crash) ────

  test(
    '5. multi-turn conversation — sandbox mode survives sequential SSE',
    () async {
      // Turn 1
      final t1 = await session.execute('''
import json
data = json.loads(
    soliplex_new_thread("demo", "cooking", "What is bruschetta?")
)
thread_id = data["thread_id"]
r1 = data["response"]
r1
''');
      print('  Turn 1: ${_trunc(t1.value?.dartValue as String, 100)}');

      // Turn 2 — uses thread_id from persisted state
      final t2 = await session.execute('''
import json
data = json.loads(
    soliplex_reply_thread("demo", "cooking", thread_id, "What bread is best?")
)
r2 = data["response"]
r2
''');
      print('  Turn 2: ${_trunc(t2.value?.dartValue as String, 100)}');
      expect(t2.value?.dartValue, isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  // ── 4. bwrap_sandbox generates monty code, we execute it ───────────

  test(
    '6. bwrap_sandbox generates monty code → we execute it',
    () async {
      // Step 1: Ask bwrap_sandbox to generate a program
      final gen = await session.execute('''
import json
prompt = """You have these Python host functions available:

  soliplex_list_servers() -> JSON string of [{id}]
  soliplex_list_rooms(server) -> JSON string of [{id, name, description}]
  soliplex_get_room(server, room_id) -> JSON string with room config

Write a short Python program that:
1. Lists all servers
2. For the first server, lists all rooms
3. Returns a dict with server_id and room names

Return ONLY the Python code in a ```monty``` code block."""

data = json.loads(
    soliplex_new_thread("local", "bwrap_sandbox", prompt)
)
generated = data["response"]
generated
''');
      final generated = gen.value?.dartValue as String;
      print('  Generated code:');
      print('  ${generated.replaceAll('\n', '\n  ')}');

      // Step 2: Extract code from ```monty``` or ```python``` block
      final codeBlock = await session.execute('''
import re
pattern = r'```(?:monty|python)\n(.*?)```'
match = re.search(pattern, generated, re.DOTALL)
code = match.group(1) if match else generated
code
''');
      final code = codeBlock.value?.dartValue as String;
      print('  Extracted code:');
      print('  ${code.replaceAll('\n', '\n  ')}');

      // Step 3: Execute the generated code
      final result = await session.execute(code);
      final output = result.value?.dartValue;
      print('  Execution result: $output');
      expect(output, isNotNull);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // ── 5. Cross-server: ask bwrap to write code that talks to demo ────

  test(
    '7. bwrap generates code that talks to demo server',
    () async {
      final gen = await session.execute('''
import json
prompt = """You have these Python host functions:

  soliplex_list_rooms(server) -> JSON string
  soliplex_get_room(server, room_id) -> JSON string
  soliplex_new_thread(server, room_id, message) -> JSON string

Write a Python program that:
1. Gets the room config for the "cooking" room on server "demo"
2. Starts a conversation asking "What is the simplest pasta recipe?"
3. Returns a dict with room_name and the agent response

Return ONLY the code in a ```monty``` block. No explanation."""

data = json.loads(
    soliplex_new_thread("local", "bwrap_sandbox", prompt)
)
gen_code = data["response"]
gen_code
''');
      final genCode = gen.value?.dartValue as String;
      print('  bwrap generated:');
      print('  ${_trunc(genCode, 300)}');

      // Extract and execute
      final extracted = await session.execute('''
import re
pattern = r'```(?:monty|python)\n(.*?)```'
match = re.search(pattern, gen_code, re.DOTALL)
code = match.group(1) if match else gen_code
code
''');
      final code = extracted.value?.dartValue as String;
      print('  Extracted code:');
      print('  ${code.replaceAll('\n', '\n  ')}');

      final result = await session.execute(code);
      final output = result.value?.dartValue;
      print('  Result: $output');
      expect(output, isNotNull);
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
