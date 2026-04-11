// ignore_for_file: avoid_print
/// Experiments with Qwen 8B and 35B via vLLM on spark-3b12
import 'dart:io';

import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:fe_plugin_soliplex/fe_plugin_soliplex.dart';
import 'package:soliplex_client/soliplex_client.dart';

Future<void> main() async {
  final transport = HttpTransport(client: DartHttpClient());
  final localUrl = UrlBuilder('http://localhost:8000/api/v1');

  final session = AgentSession(
    os: OsProvider.compose({'Path.': MemoryFsProvider()}),
    plugins: [
      SoliplexPlugin(connections: {
        'local': SoliplexConnection(
          api: SoliplexApi(transport: transport, urlBuilder: localUrl),
          streamClient: AgUiStreamClient(httpTransport: transport, urlBuilder: localUrl),
        ),
      }),
      DinjaTemplatePlugin(),
      MessageBusPlugin(),
    ],
  );

  final rules = File('/Users/runyaga/dev/dart_monty/main/docs/monty-prompt-rules.md').readAsStringSync();

  // Upload rules to both rooms
  print('=== SETUP ===');

  // 8B thread
  var r = await session.execute('''
import json
t = json.loads(soliplex_new_thread("local", "qwen_8b", "Setting up for code generation."))
thread_8b = t["thread_id"]
thread_8b
''');
  print('8B thread: ${r.value?.dartValue}');

  await _upload(session, 'thread_8b', 'monty-rules.md', rules);

  // 35B thread
  r = await session.execute('''
import json
t = json.loads(soliplex_new_thread("local", "qwen_vllm", "Setting up for code generation."))
thread_35b = t["thread_id"]
thread_35b
''');
  print('35B thread: ${r.value?.dartValue}');

  await _upload(session, 'thread_35b', 'monty-rules.md', rules);
  print('Rules uploaded to both.\n');

  // === Experiment 1: Simple code gen — compare 8B vs 35B ===
  print('${"=" * 60}');
  print('EXP 1: Write a Fibonacci function');
  print('${"=" * 60}\n');

  await _askBoth(session, 
    'Read monty-rules.md. Write a monty program with a fibonacci function '
    'that returns the first 10 fibonacci numbers as a list. '
    'Follow ALL rules. Return ONLY code in a ```monty``` block.');

  // === Experiment 2: Use host functions ===
  print('${"=" * 60}');
  print('EXP 2: Discover servers and rooms');
  print('${"=" * 60}\n');

  await _askBoth(session,
    'Read monty-rules.md. Write a monty program that: '
    '1) Calls soliplex_list_servers() to get servers, '
    '2) For each server calls soliplex_list_rooms(server) to get rooms, '
    '3) Returns a dict mapping server_id to list of room names. '
    'Remember: all host functions return JSON strings — use json.loads(). '
    'Return ONLY code in a ```monty``` block.');

  // === Experiment 3: Complex — scheduling problem ===
  print('${"=" * 60}');
  print('EXP 3: Construction scheduling');
  print('${"=" * 60}\n');

  final baseline = File('/Users/runyaga/dev/soliplex-plans/tui-experiments/ioi-experiments/wave5-construction-baseline.txt').readAsStringSync();

  // Upload experiment to both
  await _upload(session, 'thread_8b', 'experiment.txt', baseline);
  await _upload(session, 'thread_35b', 'experiment.txt', baseline);

  await _askBoth(session,
    'Read monty-rules.md and experiment.txt. Write a monty program that '
    'solves the construction scheduling problem. '
    '5 jobs, dependencies, workers, weather (day1=rain). '
    'Track completed jobs as a set. Loop day by day. '
    'Return the schedule dict as the last expression. '
    'Return ONLY code in a ```monty``` block.');

  // === Experiment 4: Template + message bus ===
  print('${"=" * 60}');
  print('EXP 4: Pipeline with templates and message bus');
  print('${"=" * 60}\n');

  await _askBoth(session,
    'Read monty-rules.md. Write a monty program that: '
    '1) Calls soliplex_list_rooms("local") to get rooms, '
    '2) Uses tmpl_render to create a markdown table of room names, '
    '3) Sends the table to msg_send("reports", table), '
    '4) Reads it back with msg_recv("reports"), '
    '5) Saves it to Path("/reports/rooms.md").write_text(), '
    '6) Returns {"table_len": len(table), "saved": True}. '
    'Return ONLY code in a ```monty``` block.');

  await session.dispose();
  transport.close();
  print('\n=== ALL EXPERIMENTS COMPLETE ===');
}

Future<void> _upload(AgentSession s, String threadVar, String name, String content) async {
  final esc = content.replaceAll('\\', '\\\\').replaceAll("'''", "\\'\\'\\'");
  await s.execute("""
import json
from pathlib import Path
soliplex_upload_to_thread("local", "qwen_8b" if "$threadVar" == "thread_8b" else "qwen_vllm", $threadVar, "$name", '''$esc''')
Path("/data").mkdir(parents=True, exist_ok=True)
Path("/data/$name").write_text('''$esc''')
"ok"
""");
}

Future<void> _askBoth(AgentSession session, String prompt) async {
  for (final (label, room, threadVar) in [
    ('8B', 'qwen_8b', 'thread_8b'),
    ('35B', 'qwen_vllm', 'thread_35b'),
  ]) {
    print('--- $label ($room) ---');

    final gen = await session.execute('''
import json
resp = json.loads(soliplex_reply_thread(
    "local", "$room", $threadVar,
    ${_pyQ(prompt)}
))
gen_response = resp["response"]
gen_response
''');

    if (gen.value?.dartValue == null) {
      print('  NULL response\n');
      continue;
    }

    // Extract code
    final extract = await session.execute(r'''
import re
pattern = r"```(?:monty|python)\s*\n(.*?)```"
match = re.search(pattern, gen_response, re.DOTALL)
if match:
    code = match.group(1).strip()
elif gen_response.strip().startswith("```"):
    lines = gen_response.strip().split("\n")
    cl = []
    started = False
    for line in lines:
        if not started and line.strip().startswith("```"):
            started = True
            continue
        if started and line.strip() == "```":
            break
        if started:
            cl.append(line)
    code = "\n".join(cl) if cl else None
else:
    code = gen_response.strip() if "import" in gen_response else None
code
''');

    final code = extract.value?.dartValue as String?;
    if (code == null) {
      print('  No code extracted');
      print('  Raw: ${_trunc(gen.value!.dartValue as String, 200)}\n');
      continue;
    }

    print('  CODE (${code.length} chars):');
    print('  ${code.replaceAll('\n', '\n  ')}\n');

    // Execute
    final result = await session.execute(code);
    if (result.error != null) {
      print('  ERROR: ${result.error!.excType}: ${result.error!.message}');
      if (result.error!.lineNumber != null) print('  Line: ${result.error!.lineNumber}');
    } else {
      print('  RESULT: ${result.value?.dartValue}');
    }
    print('');
  }
}

String _pyQ(String s) {
  final e = s.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  return '"$e"';
}

String _trunc(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}...';
