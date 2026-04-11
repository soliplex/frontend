// ignore_for_file: avoid_print
/// Run each wave5 experiment on its own fresh thread, print full generated code.
import 'dart:io';

import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:fe_plugin_soliplex/fe_plugin_soliplex.dart';
import 'package:soliplex_client/soliplex_client.dart';

const _base =
    '/Users/runyaga/dev/soliplex-plans/tui-experiments/ioi-experiments';

Future<void> main() async {
  final transport = HttpTransport(client: DartHttpClient());
  final localUrl = UrlBuilder('http://localhost:8000/api/v1');

  final rules = File(
    '/Users/runyaga/dev/dart_monty/main/docs/monty-prompt-rules.md',
  ).readAsStringSync();

  final experiments = [
    (
      name: 'BASELINE',
      file: '$_base/wave5-construction-baseline.txt',
      prompt: 'Read monty-rules.md for coding rules. Read experiment.txt. '
          'Write a monty program that solves the construction scheduling. '
          '5 jobs: H1_FND(concrete_crew,outdoor), H1_FRM(framer,indoor), '
          'H1_ROF(roofer,outdoor), H2_FND(concrete_crew,outdoor), H2_FRM(framer,indoor). '
          'Deps: H1_FRM after H1_FND, H1_ROF after H1_FRM, H2_FRM after H2_FND. '
          'Workers: Bob=concrete_crew, Alice=framer, Charlie=roofer. '
          'Weather: day1=rain, day2-4=sunny. Outdoor blocked on rain. '
          'One job per worker per day. '
          'IMPORTANT: collect all day assignments FIRST, then mark jobs done AFTER the inner loop. '
          'The last expression is the schedule dict {day_number: [{job, worker}]}. '
          'Return ONLY code in a ```monty``` block.',
    ),
    (
      name: 'OPTIMAL SCHEDULE',
      file: '$_base/wave5-construction-schedule.txt',
      prompt: 'Read monty-rules.md and experiment.txt. '
          'Write monty code for OPTIMAL scheduling — finish ALL jobs as early as possible. '
          'Same 5 jobs, deps, workers, weather as before. '
          'Greedy: each day assign as many ready jobs as possible. '
          'Collect assignments first, mark done after. '
          'The last expression is the schedule dict. '
          'Return ONLY code in a ```monty``` block.',
    ),
    (
      name: 'DISRUPTION',
      file: '$_base/wave5-construction-disruption.txt',
      prompt: 'Read monty-rules.md and experiment.txt. '
          'Simulate day-by-day construction with disruptions. '
          'Same 5 jobs, deps, workers. Weather: day1=rain, day2-5=sunny. '
          'DISRUPTION: Alice the framer is sick on day 2 — cannot work. '
          'Skip her jobs that day, delay them. '
          'Collect assignments first, mark done after. '
          'Last expression = {"executed_schedule": {day: [{job,worker}]}, "disruptions": [list]}. '
          'Return ONLY code in a ```monty``` block.',
    ),
    (
      name: 'INFEASIBLE',
      file: '$_base/wave5-construction-infeasible.txt',
      prompt: 'Read monty-rules.md and experiment.txt. '
          '5 houses x 3 jobs each = 15 total jobs. 3 workers. 3-day deadline. Day1=rain. '
          'Do NOT try to build a schedule. Analyze feasibility mathematically. '
          'Count: max worker-day slots = 3 workers x 3 days = 9. Need 15. 9 < 15. '
          'Also consider: day1 rain blocks outdoor, further reducing slots. '
          'Last expression = {"status": "infeasible"/"feasible", "reason": "...", "analysis": {...}}. '
          'Return ONLY code in a ```monty``` block.',
    ),
  ];

  for (final exp in experiments) {
    print('${"=" * 70}');
    print('EXPERIMENT: ${exp.name}');
    print('${"=" * 70}\n');

    // Fresh session per experiment to avoid state issues
    final session = AgentSession(
      os: OsProvider.compose({'Path.': MemoryFsProvider()}),
      plugins: [
        SoliplexPlugin(
          connections: {
            'local': SoliplexConnection(
              api: SoliplexApi(
                transport: transport,
                urlBuilder: localUrl,
              ),
              streamClient: AgUiStreamClient(
                httpTransport: transport,
                urlBuilder: localUrl,
              ),
            ),
          },
        ),
      ],
    );

    final expContent = File(exp.file).readAsStringSync();

    // Create thread + upload
    var r = await session.execute('''
import json
from pathlib import Path
t = json.loads(soliplex_new_thread("local", "bwrap_sandbox", "Experiment: ${exp.name}"))
thread = t["thread_id"]
thread
''');
    if (r.value?.dartValue == null) {
      print('  Failed to create thread\n');
      await session.dispose();
      continue;
    }

    // Upload rules + experiment
    final rulesEsc = _esc(rules);
    final expEsc = _esc(expContent);
    await session.execute("""
import json
from pathlib import Path
soliplex_upload_to_thread("local", "bwrap_sandbox", thread, "monty-rules.md", '''$rulesEsc''')
Path("/data").mkdir(parents=True, exist_ok=True)
Path("/data/monty-rules.md").write_text('''$rulesEsc''')
soliplex_upload_to_thread("local", "bwrap_sandbox", thread, "experiment.txt", '''$expEsc''')
Path("/data/experiment.txt").write_text('''$expEsc''')
"uploaded"
""");

    // Ask for code
    r = await session.execute('''
import json
resp = json.loads(soliplex_reply_thread(
    "local", "bwrap_sandbox", thread,
    ${_pyQ(exp.prompt)}
))
gen_response = resp["response"]
gen_response
''');

    if (r.value?.dartValue == null) {
      print('  NULL response — server slow\n');
      await session.dispose();
      continue;
    }

    // Extract
    r = await session.execute(r'''
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
    code = gen_response.strip() if "schedule" in gen_response or "status" in gen_response else None
code
''');

    final code = r.value?.dartValue as String?;
    if (code == null) {
      print('  No code extracted');
      print('  Raw response: ${(r.value?.dartValue ?? "null").toString().substring(0, 200)}');
      await session.dispose();
      continue;
    }

    print('GENERATED CODE (${code.length} chars):');
    print('```python');
    print(code);
    print('```\n');

    // Execute
    final result = await session.execute(code);
    if (result.error != null) {
      print('EXECUTION ERROR: ${result.error}\n');
    } else {
      print('RESULT: ${result.value?.dartValue}\n');
    }
    if (result.printOutput?.isNotEmpty ?? false) {
      print('PRINT OUTPUT:\n${result.printOutput}\n');
    }

    await session.dispose();
  }

  transport.close();
  print('${"=" * 70}');
  print('ALL EXPERIMENTS COMPLETE');
  print('${"=" * 70}');
}

String _esc(String s) =>
    s.replaceAll('\\', '\\\\').replaceAll("'''", "\\'\\'\\'");

String _pyQ(String s) {
  final e = s.replaceAll('\\', '\\\\').replaceAll('"', '\\"');

  return '"$e"';
}
