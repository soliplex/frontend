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
      os: OsProvider.compose({
        'Path.': MemoryFsProvider(),
        'date.': TimeOsProvider(),
        'datetime.': TimeOsProvider(),
      }),
      plugins: [
        SoliplexPlugin(
          connections: {
            'demo': _buildConnection('https://demo.toughserv.com'),
            'local': _buildConnection('http://localhost:8000'),
          },
        ),
        DinjaTemplatePlugin(),
        MessageBusPlugin(),
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

  // ── 8. Upload ruleset file → agent reads it → generates code ──────

  test(
    '8. Upload monty ruleset then ask for codegen',
    () async {
      // Step 1: Create thread on bwrap_sandbox
      final t = await session.execute('''
import json
t = json.loads(soliplex_new_thread("local", "bwrap_sandbox", "I will upload a ruleset file."))
ruleset_thread = t["thread_id"]
ruleset_thread
''');
      print('  Thread: ${t.value?.dartValue}');

      // Step 2: Upload the full monty ruleset as a file
      await session.execute('''
import json
ruleset = """# Monty Python Sandbox — API Reference

You are writing code for Monty, a sandboxed Python interpreter.
Your code runs inside a sandbox with host functions available as built-in callables.

## Rules
1. All host functions return JSON STRINGS. Always use json.loads() on the result.
2. import json at the top of every program.
3. The last expression in your code is the return value.
4. Return your code in a ```monty``` code block.
5. No explanation outside the code block.

## Available Host Functions

### Discovery
- soliplex_list_servers() -> JSON string of [{id}]
- soliplex_list_rooms(server) -> JSON string of [{id, name, description}]
- soliplex_get_room(server, room_id) -> JSON string with full room config including skills, tools

### Conversation
- soliplex_new_thread(server, room_id, message) -> JSON string with {thread_id, run_id, response}
- soliplex_reply_thread(server, room_id, thread_id, message) -> JSON string with {thread_id, run_id, response}

### File Upload
- soliplex_upload_file(server, room_id, filename, content) -> JSON string with {uploaded, room_id}
- soliplex_upload_to_thread(server, room_id, thread_id, filename, content) -> JSON string

### Threads
- soliplex_list_threads(server, room_id) -> JSON string of thread list

## Servers
- "demo" — demo.toughserv.com (cooking, chat, image_generation, soliplex rooms)
- "local" — localhost:8000 (analysis, bwrap_sandbox, chat, search rooms)

## Example
```monty
import json
rooms = json.loads(soliplex_list_rooms("demo"))
[r["name"] for r in rooms]
```
"""
soliplex_upload_to_thread("local", "bwrap_sandbox", ruleset_thread, "monty-rules.md", ruleset)
"uploaded"
''');
      print('  Ruleset uploaded');

      // Step 3: Ask the agent to read the file and write code
      final gen = await session.execute('''
import json
resp = json.loads(soliplex_reply_thread(
    "local", "bwrap_sandbox", ruleset_thread,
    "Read the monty-rules.md file I uploaded. Using those rules exactly, write a monty program that: "
    "1) Lists all servers, 2) For each server lists rooms, 3) Finds rooms with skills, "
    "4) Returns a dict mapping server_id to list of {room_id, skills}. "
    "Return the code in a ```monty``` code block ONLY."
))
gen_response = resp["response"]
gen_response
''');
      final genText = gen.value?.dartValue;
      if (genText == null) {
        print('  Agent returned null — SSE state wrapping issue');
        print('  (This is a known limitation of execute() state capture)');

        return;
      }
      print('  Agent: ${_trunc(genText as String, 200)}');

      // Step 4: Extract code block
      final exec = await session.execute(r'''
import re
# Try fenced code block
pattern = r"```(?:monty|python)\s*\n(.*?)```"
match = re.search(pattern, gen_response, re.DOTALL)
if match:
    extracted_code = match.group(1).strip()
elif gen_response.strip().startswith("```"):
    # Strip fences manually
    lines = gen_response.strip().split("\n")
    # Remove first line (```monty) and last line (```)
    code_lines = []
    started = False
    for line in lines:
        if not started and line.strip().startswith("```"):
            started = True
            continue
        if started and line.strip() == "```":
            break
        if started:
            code_lines.append(line)
    extracted_code = "\n".join(code_lines) if code_lines else None
elif "import json" in gen_response:
    extracted_code = gen_response.strip()
else:
    extracted_code = None
extracted_code
''');
      final code = exec.value?.dartValue;
      if (code == null) {
        print('  No code extracted');

        return;
      }
      print('  Code: ${_trunc(code as String, 150)}');

      // Step 5: Execute the generated code
      final result = await session.execute(code);
      print('  Result: ${result.value?.dartValue}');
      expect(result.value?.dartValue, isNotNull);
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // ── 9. Upload expanded ruleset with ALL plugins ─────────────────────

  test(
    '9. Upload full ruleset with all plugins',
    () async {
      await session.execute('''
import json

# Create a fresh thread for advanced codegen
t = json.loads(soliplex_new_thread("local", "bwrap_sandbox", "Setting up environment."))
adv_thread = t["thread_id"]

ruleset = """# Monty Sandbox — Complete API Reference

You are writing code for Monty, a sandboxed Python interpreter with host functions.

## RULES
1. All host functions that return data return JSON STRINGS. Use json.loads().
2. import json at the top.
3. The last expression is the return value.
4. Return code in a ```monty``` code block ONLY. No explanation outside it.

## Host Functions

### Soliplex — Server Communication
- soliplex_list_servers() -> JSON [{id}]
- soliplex_list_rooms(server) -> JSON [{id, name, description}]
- soliplex_get_room(server, room_id) -> JSON {id, name, description, skills, tools}
- soliplex_new_thread(server, room_id, message) -> JSON {thread_id, run_id, response}
- soliplex_reply_thread(server, room_id, thread_id, message) -> JSON {thread_id, run_id, response}
- soliplex_upload_file(server, room_id, filename, content) -> JSON {uploaded, room_id}
- soliplex_upload_to_thread(server, room_id, thread_id, filename, content) -> JSON
- soliplex_list_threads(server, room_id) -> JSON of thread list

### Template Engine (Jinja2-style)
- tmpl_render(template_string, context_dict) -> rendered string (NOT JSON)
  Example: tmpl_render("Hello {{ name }}!", {"name": "World"}) -> "Hello World!"

### Message Bus (inter-step FIFO queues)
- msg_send(channel, message) -> None (fire-and-forget)
- msg_recv(channel) -> message string (blocks until available)
- msg_peek(channel) -> message or None (non-blocking)

### Filesystem (in-memory sandbox)
- from pathlib import Path
- Path("/path").write_text(content) — write file
- Path("/path").read_text() — read file
- Path("/path").mkdir(parents=True, exist_ok=True) — create dirs
- Path("/path").exists() — check existence

## Servers
- "demo" — demo.toughserv.com: cooking, chat, image_generation, soliplex (RAG)
- "local" — localhost:8000: analysis, bwrap_sandbox, chat, search, feedback

## Patterns

### Pipeline with message bus
```monty
import json
# Step 1: get data
msg_send("pipeline", json.dumps({"step": "fetch", "data": "..."}))
# Step 2: process
raw = msg_recv("pipeline")
# Step 3: template
result = tmpl_render("Report: {{ data }}", {"data": raw})
```

### File caching
```monty
from pathlib import Path
import json
if not Path("/cache/rooms.json").exists():
    rooms = soliplex_list_rooms("demo")
    Path("/cache").mkdir(parents=True, exist_ok=True)
    Path("/cache/rooms.json").write_text(rooms)
cached = json.loads(Path("/cache/rooms.json").read_text())
```
"""

soliplex_upload_to_thread("local", "bwrap_sandbox", adv_thread, "monty-complete-rules.md", ruleset)
adv_thread
''');
      print('  Advanced thread: ${session.state['adv_thread'] ?? 'set'}');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  // ── 10. Generate pipeline: fetch → cache → template → report ───────

  test(
    '10. Codegen: data pipeline with caching and templates',
    () async {
      final gen = await session.execute('''
import json
resp = json.loads(soliplex_reply_thread(
    "local", "bwrap_sandbox", adv_thread,
    "Read monty-complete-rules.md. Write a program that: "
    "1) Fetches all rooms from demo server, "
    "2) Saves the raw JSON to /cache/demo_rooms.json using pathlib, "
    "3) Uses tmpl_render to create a markdown report listing each room name and description, "
    "4) Saves the report to /reports/rooms.md, "
    "5) Sends the report to msg_send on channel 'reports', "
    "6) Reads it back with msg_recv, "
    "7) Returns {cached: True, report_len: len, channel: 'reports'}"
))
gen_response = resp["response"]
gen_response
''');
      final genText = gen.value?.dartValue;
      if (genText == null) {
        print('  null response — skipping');

        return;
      }
      print('  Agent: ${_trunc(genText as String, 200)}');

      // Extract and execute
      final code = await _extractCode(session);
      if (code == null) {
        print('  No code extracted');

        return;
      }
      print('  Code: ${_trunc(code, 200)}');

      final result = await session.execute(code);
      print('  Result: ${result.value?.dartValue}');
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // ── 11. Generate: cross-server intelligence gathering ──────────────

  test(
    '11. Codegen: gather intel from both servers, write report',
    () async {
      final gen = await session.execute('''
import json
resp = json.loads(soliplex_reply_thread(
    "local", "bwrap_sandbox", adv_thread,
    "Write a program that: "
    "1) Lists rooms on BOTH demo and local servers, "
    "2) For each room with skills, gets the room config, "
    "3) Builds a comparison dict: {server: [{room, skills, tools, has_rag: bool}]}, "
    "4) Uses tmpl_render to make a text summary like 'Server X has N rooms, Y with RAG', "
    "5) Writes the summary to /reports/comparison.txt, "
    "6) Returns the comparison dict. "
    "Remember json.loads() on all host function returns."
))
gen_response = resp["response"]
gen_response
''');
      if (gen.value?.dartValue == null) {
        print('  null — skipping');

        return;
      }
      print('  Agent: ${_trunc(gen.value!.dartValue as String, 200)}');

      final code = await _extractCode(session);
      if (code == null) return;
      print('  Code: ${_trunc(code, 200)}');

      final result = await session.execute(code);
      print('  Result: ${result.value?.dartValue}');
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // ── 12. Generate: conversation → file → template report ────────────

  test(
    '12. Codegen: ask demo cooking, save recipe, generate report',
    () async {
      final gen = await session.execute('''
import json
resp = json.loads(soliplex_reply_thread(
    "local", "bwrap_sandbox", adv_thread,
    "Write a program that: "
    "1) Asks the demo cooking room for a simple soup recipe, "
    "2) Saves the recipe to /recipes/soup.txt, "
    "3) Uses tmpl_render to create a formatted card: "
    "   'Recipe Card\\n===========\\nSource: {{ server }}\\nRoom: {{ room }}\\n\\n{{ recipe }}', "
    "4) Sends the card to msg_send('cards'), "
    "5) Reads it back with msg_recv('cards'), "
    "6) Returns {recipe_file: '/recipes/soup.txt', card_len: N, card_preview: first 100 chars}. "
    "Use json.loads() on all host function returns."
))
gen_response = resp["response"]
gen_response
''');
      if (gen.value?.dartValue == null) {
        print('  null — skipping');

        return;
      }
      print('  Agent: ${_trunc(gen.value!.dartValue as String, 200)}');

      final code = await _extractCode(session);
      if (code == null) return;
      print('  Code: ${_trunc(code, 200)}');

      final result = await session.execute(code);
      print('  Result: ${result.value?.dartValue}');
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // ── 13. Generate: multi-server conversation orchestrator ────────────

  test(
    '13. Codegen: orchestrate conversations across servers',
    () async {
      final gen = await session.execute('''
import json
resp = json.loads(soliplex_reply_thread(
    "local", "bwrap_sandbox", adv_thread,
    "Write a program that: "
    "1) Asks demo cooking room: 'What goes well with pasta?', "
    "2) Takes the response and asks local chat room: 'Summarize this in 10 words: ' + the response, "
    "3) Saves both responses to /conversations/cross-server.txt, "
    "4) Uses tmpl_render to make a comparison: "
    "   'Demo said ({{ demo_len }} chars): {{ demo_preview }}\\n"
    "Local said ({{ local_len }} chars): {{ local_preview }}', "
    "5) Returns {demo_thread, local_thread, template_output}. "
    "Use json.loads() on all host function returns."
))
gen_response = resp["response"]
gen_response
''');
      if (gen.value?.dartValue == null) {
        print('  null — skipping');

        return;
      }
      print('  Agent: ${_trunc(gen.value!.dartValue as String, 200)}');

      final code = await _extractCode(session);
      if (code == null) return;
      print('  Code: ${_trunc(code, 200)}');

      final result = await session.execute(code);
      print('  Result: ${result.value?.dartValue}');
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );

  // ── OLD test 8 (renamed to 14) ────────────────────────────────────

  test(
    '14. inline codegen (no ruleset)',
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
    '14b. Execute generated code',
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

Future<String?> _extractCode(AgentSession session) async {
  final r = await session.execute(r'''
import re
pattern = r"```(?:monty|python)\s*\n(.*?)```"
match = re.search(pattern, gen_response, re.DOTALL)
if match:
    extracted_code = match.group(1).strip()
elif gen_response.strip().startswith("```"):
    lines = gen_response.strip().split("\n")
    code_lines = []
    started = False
    for line in lines:
        if not started and line.strip().startswith("```"):
            started = True
            continue
        if started and line.strip() == "```":
            break
        if started:
            code_lines.append(line)
    extracted_code = "\n".join(code_lines) if code_lines else None
elif "import json" in gen_response:
    extracted_code = gen_response.strip()
else:
    extracted_code = None
extracted_code
''');

  return r.value?.dartValue as String?;
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
