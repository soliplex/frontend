// Advanced multi-server scenarios — print is used for output.
// ignore_for_file: avoid_print, cast_nullable_to_non_nullable
@Tags(['integration'])
library;

import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:fe_plugin_soliplex/fe_plugin_soliplex.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

/// Advanced cross-server scenarios exercising the full pipeline:
/// AgentSession → SoliplexPlugin → multiple servers → SSE → codegen → execute
///
/// Run:
///   dart test test/integration/advanced_scenarios_test.dart -t integration --reporter expanded
void main() {
  late AgentSession session;

  setUpAll(() {
    session = AgentSession(
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

  // ── 1. Cross-server discovery ──────────────────────────────────────

  test(
    '1. Python discovers all rooms on both servers',
    () async {
      final r = await session.execute('''
import json

servers = json.loads(soliplex_list_servers())
report = {}
for s in servers:
    sid = s["id"]
    rooms = json.loads(soliplex_list_rooms(sid))
    report[sid] = {
        "count": len(rooms),
        "ids": [r["id"] for r in rooms],
    }
report
''');
      final report = r.value?.dartValue as Map;
      print('  Demo: ${report["demo"]}');
      print('  Local: ${report["local"]}');
      expect((report['demo'] as Map)['count'] as int, greaterThan(0));
      expect((report['local'] as Map)['count'] as int, greaterThan(0));
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  // ── 2. Cross-server room comparison ────────────────────────────────

  test(
    '2a. Find skilled rooms on demo',
    () async {
      final r = await session.execute('''
import json
rooms = json.loads(soliplex_list_rooms("demo"))
demo_skilled = []
for room in rooms:
    config = json.loads(soliplex_get_room("demo", room["id"]))
    if config.get("skills"):
        demo_skilled.append({"id": room["id"], "skills": config["skills"]})
demo_skilled
''');
      final result = r.value?.dartValue as List;
      print('  Demo skilled: $result');
      expect(result, isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  test(
    '2b. Find skilled rooms on local',
    () async {
      final r = await session.execute('''
import json
rooms = json.loads(soliplex_list_rooms("local"))
local_skilled = []
for room in rooms:
    config = json.loads(soliplex_get_room("local", room["id"]))
    if config.get("skills"):
        local_skilled.append({"id": room["id"], "skills": config["skills"]})
local_skilled
''');
      final result = r.value?.dartValue as List;
      print('  Local skilled: $result');
      expect(result, isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  // ── 3. Talk to demo cooking, summarize for local ───────────────────

  test(
    '3. Get recipe from demo, upload summary to local',
    () async {
      final r = await session.execute('''
import json

# Ask demo cooking for a recipe
t = json.loads(soliplex_new_thread("demo", "cooking", "Give me a 3-step recipe for garlic bread"))
recipe = t["response"]
demo_thread = t["thread_id"]

# Upload the recipe as a file to local bwrap_sandbox room
soliplex_upload_file("local", "bwrap_sandbox", "demo-recipe.txt", recipe)

{"recipe_len": len(recipe), "demo_thread": demo_thread, "uploaded": True}
''');
      final result = r.value?.dartValue as Map;
      print('  Recipe: ${result["recipe_len"]} chars');
      print('  Thread: ${result["demo_thread"]}');
      print('  Uploaded to local: ${result["uploaded"]}');
      expect(result['recipe_len'] as int, greaterThan(0));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  // ── 4. Multi-turn on demo, cross-reference with local ──────────────

  test(
    '4a. Demo 3-turn: pad thai conversation',
    () async {
      // Turn 1
      final t1 = await session.execute('''
import json
t1 = json.loads(soliplex_new_thread("demo", "cooking", "What is pad thai?"))
pad_thread = t1["thread_id"]
t1_resp = t1["response"]
len(t1_resp)
''');
      print('  Turn 1: ${t1.value?.dartValue} chars');

      // Turn 2
      final t2 = await session.execute('''
import json
t2 = json.loads(soliplex_reply_thread("demo", "cooking", pad_thread, "List the main ingredients"))
t2_resp = t2["response"]
len(t2_resp)
''');
      print('  Turn 2: ${t2.value?.dartValue} chars');

      // Turn 3
      final t3 = await session.execute('''
import json
t3 = json.loads(soliplex_reply_thread("demo", "cooking", pad_thread, "How long to cook?"))
t3_resp = t3["response"]
t3_resp[:100]
''');
      print('  Turn 3: ${_trunc(t3.value?.dartValue as String, 100)}');
      expect(t3.value?.dartValue, isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  test(
    '4b. Cross-server: send demo result to local',
    () async {
      final r = await session.execute('''
import json
summary = "Pad thai cooking info: " + t3_resp[:200]
local_t = json.loads(soliplex_new_thread("local", "chat", "One sentence summary: " + summary))
local_t["response"][:200]
''');
      print('  Local summary: ${_trunc(r.value?.dartValue as String, 120)}');
      expect(r.value?.dartValue, isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  // ── 5. bwrap generates code that queries demo ──────────────────────

  test(
    '5. bwrap codegen → code queries demo → execute result',
    () async {
      final r = await session.execute('''
import json
import re

# Step 1: Ask bwrap to generate code
prompt = """You are writing code for Monty, a Python sandbox. Available host functions:

  soliplex_list_rooms(server) -> JSON string. Call json.loads() on the result.
  soliplex_get_room(server, room_id) -> JSON string. Call json.loads() on the result.

RULES:
- All host function return values are JSON STRINGS. Always use json.loads().
- import json at the top.
- The last expression in the code is the return value.
- Return ONLY code in a ```monty``` code block. No explanation.

Write a program that:
1. Lists rooms on server "demo"
2. Finds the cooking room
3. Gets its config
4. Returns a dict with room_name and description"""

gen = json.loads(soliplex_new_thread("local", "bwrap_sandbox", prompt))
generated = gen["response"]

# Step 2: Extract code block
pattern = r"```(?:monty|python)\n(.*?)```"
match = re.search(pattern, generated, re.DOTALL)
code = match.group(1) if match else None
code
''');
      final code = r.value?.dartValue;
      if (code == null) {
        print('  No code block extracted — skipping execution');

        return;
      }
      print('  Generated code (${(code as String).length} chars):');
      print('  ${_trunc(code, 200)}');

      // Step 3: Execute the generated code
      final exec = await session.execute(code);
      final result = exec.value?.dartValue;
      print('  Execution result: $result');
      expect(result, isNotNull);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // ── 6. bwrap generates code that has a conversation on demo ────────

  test(
    '6. bwrap codegen → code has conversation on demo cooking',
    () async {
      final r = await session.execute('''
import json
import re

prompt = """You are writing code for Monty, a Python sandbox. Available host functions:

  soliplex_new_thread(server, room_id, message) -> JSON string with {thread_id, run_id, response}
  soliplex_reply_thread(server, room_id, thread_id, message) -> JSON string with {thread_id, run_id, response}

RULES:
- All host function return values are JSON STRINGS. Always use json.loads().
- import json at the top.
- The last expression is the return value.
- Return ONLY code in a ```monty``` block. No explanation.

Write a program that:
1. Starts a conversation on server "demo", room "cooking", asking "What is risotto?"
2. Replies asking "What rice should I use?"
3. Returns {"turn1": first_response, "turn2": second_response}"""

gen = json.loads(soliplex_new_thread("local", "bwrap_sandbox", prompt))
generated = gen["response"]

pattern = r"```(?:monty|python)\n(.*?)```"
match = re.search(pattern, generated, re.DOTALL)
code = match.group(1) if match else None
code
''');
      final code = r.value?.dartValue;
      if (code == null) {
        print('  No code block — skipping');

        return;
      }
      print('  Code (${(code as String).length} chars):');
      print('  ${_trunc(code, 200)}');

      final exec = await session.execute(code);
      final result = exec.value?.dartValue;
      print('  Result: ${result is Map ? _truncMap(result) : result}');
      expect(result, isNotNull);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // ── 7. Round-trip: demo → file → local reads it ────────────────────

  test(
    '7a. Get recipe from demo + upload to local',
    () async {
      final r = await session.execute('''
import json
recipe_data = json.loads(
    soliplex_new_thread("demo", "cooking", "Give me a simple 2-step pancake recipe, very short")
)
pancake_recipe = recipe_data["response"]
soliplex_upload_file("local", "bwrap_sandbox", "pancake.txt", pancake_recipe)
len(pancake_recipe)
''');
      print('  Recipe: ${r.value?.dartValue} chars');
      expect(r.value?.dartValue as int, greaterThan(0));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    '7b. Local comments on uploaded recipe',
    () async {
      final r = await session.execute('''
import json
local_resp = json.loads(
    soliplex_new_thread("local", "chat", "Comment on this recipe in one sentence: " + pancake_recipe[:300])
)
local_resp["response"][:200]
''');
      print('  Local: ${_trunc(r.value?.dartValue as String, 120)}');
      expect(r.value?.dartValue, isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  // ── 8. Iterative codegen: generate, error, correct, execute ────────

  test(
    '8a. bwrap generates code',
    () async {
      final r = await session.execute('''
import json
import re

prompt = """You are writing code for Monty, a Python sandbox. Available host functions:

  soliplex_list_rooms(server) -> JSON string of [{id, name, description}]

RULES:
- All host function return values are JSON STRINGS. Always use json.loads().
- import json at the top.
- The last expression is the return value.
- Return ONLY code in a ```monty``` block. No explanation.

Write a program that lists rooms on server "demo" and returns the room names as a Python list."""

gen = json.loads(soliplex_new_thread("local", "bwrap_sandbox", prompt))
codegen_raw = gen["response"]
codegen_thread = gen["thread_id"]

pattern = r"```(?:monty|python)\n(.*?)```"
match = re.search(pattern, codegen_raw, re.DOTALL)
codegen_code = match.group(1) if match else None
codegen_code[:200] if codegen_code else "no code block"
''');
      print('  Code: ${_trunc(r.value?.dartValue as String, 150)}');
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    '8b. Execute generated code',
    () async {
      final r = await session.execute('''
result = None
if codegen_code:
    result = codegen_code
result
''');
      final code = r.value?.dartValue;
      if (code == null) {
        print('  No code to execute');

        return;
      }
      // Execute the generated code
      final exec = await session.execute(code as String);
      print('  Result: ${exec.value?.dartValue}');
      expect(exec.value?.dartValue, isNotNull);
    },
    timeout: const Timeout(Duration(seconds: 30)),
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

String _truncMap(Map<dynamic, dynamic> m) {
  final buf = StringBuffer('{');
  for (final e in m.entries) {
    final v = e.value is String ? _trunc(e.value as String, 80) : e.value;
    buf.write('${e.key}: $v, ');
  }
  buf.write('}');

  return buf.toString();
}
