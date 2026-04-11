// ignore_for_file: avoid_print
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
    ],
  );

  final rules = File('/Users/runyaga/dev/dart_monty/main/docs/monty-prompt-rules.md').readAsStringSync();
  final disruption = File('/Users/runyaga/dev/soliplex-plans/tui-experiments/ioi-experiments/wave5-construction-disruption.txt').readAsStringSync();

  // Fresh thread, upload rules + ONE experiment, write to sandbox fs
  print('Setting up...');
  var r = await session.execute('''
import json
from pathlib import Path
t = json.loads(soliplex_new_thread("local", "bwrap_sandbox", "Disruption scheduling experiment."))
thread = t["thread_id"]
thread
''');
  print('Thread: ${r.value?.dartValue}');

  // Upload rules to thread + sandbox
  final rulesEsc = rules.replaceAll('\\', '\\\\').replaceAll("'''", "\\'\\'\\'");
  await session.execute("""
import json
from pathlib import Path
soliplex_upload_to_thread("local", "bwrap_sandbox", thread, "monty-rules.md", '''$rulesEsc''')
Path("/data").mkdir(parents=True, exist_ok=True)
Path("/data/monty-rules.md").write_text('''$rulesEsc''')
"ok"
""");
  print('Rules uploaded');

  // Upload disruption to thread + sandbox
  final disrEsc = disruption.replaceAll('\\', '\\\\').replaceAll("'''", "\\'\\'\\'");
  await session.execute("""
import json
from pathlib import Path
soliplex_upload_to_thread("local", "bwrap_sandbox", thread, "disruption.txt", '''$disrEsc''')
Path("/data/disruption.txt").write_text('''$disrEsc''')
"ok"
""");
  print('Disruption uploaded');

  // Ask for code
  print('\nAsking bwrap for code...');
  r = await session.execute('''
import json
resp = json.loads(soliplex_reply_thread(
    "local", "bwrap_sandbox", thread,
    "Read monty-rules.md and disruption.txt. The disruption data is at /data/disruption.txt in the sandbox. "
    "Write monty code that simulates day-by-day construction with disruptions. "
    "Alice the framer is sick on day 2. Weather: day1=rain, day2-5=sunny. "
    "5 jobs: H1_FND(concrete_crew,outdoor), H1_FRM(framer,indoor), H1_ROF(roofer,outdoor), "
    "H2_FND(concrete_crew,outdoor), H2_FRM(framer,indoor). "
    "Deps: H1_FRM after H1_FND, H1_ROF after H1_FRM, H2_FRM after H2_FND. "
    "Workers: Bob=concrete_crew, Alice=framer, Charlie=roofer. "
    "Rules: use = not :=, d[\\"key\\"] not d.key, no open(), use Path().read_text(), "
    "no % formatting, use f-strings, no enumerate(start=). "
    "Collect day assignments FIRST, mark done AFTER. "
    "Return {executed_schedule: {day: [assignments]}, disruptions: [list]}. "
    "Return ONLY code in a ```monty``` block."
))
gen_response = resp["response"]
gen_response
''');

  if (r.value?.dartValue == null) {
    print('NULL response — server issue');
    await session.dispose();
    transport.close();
    return;
  }

  final genText = r.value!.dartValue as String;
  print('Response (${genText.length} chars)');

  // Extract
  r = await session.execute(r"""
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
    code = None
code
""");

  final code = r.value?.dartValue as String?;
  if (code == null) {
    print('No code extracted');
    await session.dispose();
    transport.close();
    return;
  }

  print('\n--- GENERATED CODE ---');
  print(code);
  print('--- END ---\n');

  final result = await session.execute(code);
  print('Result: ${result.value?.dartValue}');
  if (result.error != null) print('Error: ${result.error}');

  await session.dispose();
  transport.close();
}
