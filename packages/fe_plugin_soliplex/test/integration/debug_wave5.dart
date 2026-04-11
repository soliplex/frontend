// ignore_for_file: avoid_print
import 'dart:io';
import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:fe_plugin_soliplex/fe_plugin_soliplex.dart';
import 'package:soliplex_client/soliplex_client.dart';

Future<void> main() async {
  final transport = HttpTransport(client: DartHttpClient());
  final localUrl = UrlBuilder('http://localhost:8000/api/v1');
  final demoUrl = UrlBuilder('https://demo.toughserv.com/api/v1');
  final demoTransport = HttpTransport(client: DartHttpClient());

  final session = AgentSession(
    os: OsProvider.compose({'Path.': MemoryFsProvider()}),
    plugins: [
      SoliplexPlugin(connections: {
        'demo': SoliplexConnection(
          api: SoliplexApi(transport: demoTransport, urlBuilder: demoUrl),
          streamClient: AgUiStreamClient(httpTransport: demoTransport, urlBuilder: demoUrl),
        ),
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
  final baseline = File('/Users/runyaga/dev/soliplex-plans/tui-experiments/ioi-experiments/wave5-construction-baseline.txt').readAsStringSync();
  final schedule = File('/Users/runyaga/dev/soliplex-plans/tui-experiments/ioi-experiments/wave5-construction-schedule.txt').readAsStringSync();
  final disruption = File('/Users/runyaga/dev/soliplex-plans/tui-experiments/ioi-experiments/wave5-construction-disruption.txt').readAsStringSync();
  final infeasible = File('/Users/runyaga/dev/soliplex-plans/tui-experiments/ioi-experiments/wave5-construction-infeasible.txt').readAsStringSync();

  // Create thread and upload everything
  print('=== Setup ===');
  var r = await session.execute('''
import json
t = json.loads(soliplex_new_thread("local", "bwrap_sandbox", "Setting up construction scheduling experiments."))
thread = t["thread_id"]
thread
''');
  final threadId = r.value?.dartValue as String;
  print('Thread: $threadId');

  // Upload rules
  await session.execute(_upload('monty-rules.md', rules));
  print('Rules uploaded');

  // Upload all experiments
  await session.execute(_upload('baseline.txt', baseline));
  await session.execute(_upload('schedule.txt', schedule));
  await session.execute(_upload('disruption.txt', disruption));
  await session.execute(_upload('infeasible.txt', infeasible));
  print('All 4 experiments uploaded\n');

  // === Experiment 1: Baseline ===
  print('=== Experiment 1: Baseline Scheduling ===');
  r = await session.execute('''
import json
resp = json.loads(soliplex_reply_thread(
    "local", "bwrap_sandbox", thread,
    "Read monty-rules.md for coding rules. Read baseline.txt for the problem. "
    "Write a monty program that solves the construction scheduling. "
    "Use a Python dict as the blackboard. Track: "
    "- jobs dict with name, role, weather_type (outdoor/indoor), dependencies, status "
    "- workers dict mapping name to role "
    "- weather list per day "
    "Loop day by day. On each day: skip outdoor jobs if rain, find ready jobs "
    "(deps all done), assign matching workers (one job per worker per day). "
    "The last expression should be the schedule dict. "
    "Return ONLY code in a ```monty``` block."
))
gen_response = resp["response"]
gen_response
''');
  final baseline_code = await _extract(session);
  if (baseline_code != null) {
    print('--- GENERATED CODE (${baseline_code.length} chars) ---');
    print(baseline_code);
    print('--- END CODE ---\n');

    print('--- EXECUTING ---');
    final result = await session.execute(baseline_code);
    print('Result: ${result.value?.dartValue}');
    if (result.error != null) print('Error: ${result.error}');
    if (result.printOutput?.isNotEmpty ?? false) print('Output:\n${result.printOutput}');
    print('--- END EXECUTION ---\n');
  } else {
    print('No code extracted\n');
  }

  // === Experiment 2: Optimal Schedule ===
  print('=== Experiment 2: Optimal Schedule ===');
  r = await session.execute('''
import json
resp = json.loads(soliplex_reply_thread(
    "local", "bwrap_sandbox", thread,
    "Read schedule.txt. Write monty code for OPTIMAL scheduling — finish all jobs ASAP. "
    "Same setup: jobs with deps, workers with roles, weather per day. "
    "Outdoor jobs blocked on rain. One job per worker per day. "
    "Greedy: each day schedule as many ready jobs as possible. "
    "Return the schedule as the last expression. ```monty``` block only."
))
gen_response = resp["response"]
gen_response
''');
  final schedule_code = await _extract(session);
  if (schedule_code != null) {
    print('--- GENERATED CODE (${schedule_code.length} chars) ---');
    print(schedule_code);
    print('--- END CODE ---\n');

    print('--- EXECUTING ---');
    final result = await session.execute(schedule_code);
    print('Result: ${result.value?.dartValue}');
    if (result.error != null) print('Error: ${result.error}');
    if (result.printOutput?.isNotEmpty ?? false) print('Output:\n${result.printOutput}');
    print('--- END EXECUTION ---\n');
  } else {
    print('No code extracted\n');
  }

  // === Experiment 3: Disruption ===
  print('=== Experiment 3: Disruption ===');
  r = await session.execute('''
import json
resp = json.loads(soliplex_reply_thread(
    "local", "bwrap_sandbox", thread,
    "Read disruption.txt. Write monty code that simulates day-by-day with disruptions. "
    "Alice (framer) is sick on day 2. When sick, delay her jobs. "
    "Same rules: deps, weather, one job per worker per day. "
    "Track executed_schedule (what actually happened) and disruptions list. "
    "Return dict with both as the last expression. ```monty``` block only."
))
gen_response = resp["response"]
gen_response
''');
  final disruption_code = await _extract(session);
  if (disruption_code != null) {
    print('--- GENERATED CODE (${disruption_code.length} chars) ---');
    print(disruption_code);
    print('--- END CODE ---\n');

    print('--- EXECUTING ---');
    final result = await session.execute(disruption_code);
    print('Result: ${result.value?.dartValue}');
    if (result.error != null) print('Error: ${result.error}');
    if (result.printOutput?.isNotEmpty ?? false) print('Output:\n${result.printOutput}');
    print('--- END EXECUTION ---\n');
  } else {
    print('No code extracted\n');
  }

  // === Experiment 4: Infeasible ===
  print('=== Experiment 4: Infeasible Analysis ===');
  r = await session.execute('''
import json
resp = json.loads(soliplex_reply_thread(
    "local", "bwrap_sandbox", thread,
    "Read infeasible.txt. 5 houses x 3 jobs = 15 jobs, 3 workers, 3-day deadline. "
    "Day 1 is rain (blocks outdoor). Write monty code that: "
    "1) Calculates max jobs per day per worker = 3 workers x 3 days = 9 slots "
    "2) But day 1 rain blocks outdoor = fewer slots "
    "3) Count how many outdoor vs indoor jobs need scheduling "
    "4) Determine if feasible "
    "5) Return {status: 'feasible'/'infeasible', reason: '...', analysis: {...}} "
    "```monty``` block only."
))
gen_response = resp["response"]
gen_response
''');
  final infeasible_code = await _extract(session);
  if (infeasible_code != null) {
    print('--- GENERATED CODE (${infeasible_code.length} chars) ---');
    print(infeasible_code);
    print('--- END CODE ---\n');

    print('--- EXECUTING ---');
    final result = await session.execute(infeasible_code);
    print('Result: ${result.value?.dartValue}');
    if (result.error != null) print('Error: ${result.error}');
    if (result.printOutput?.isNotEmpty ?? false) print('Output:\n${result.printOutput}');
    print('--- END EXECUTION ---\n');
  } else {
    print('No code extracted\n');
  }

  await session.dispose();
  transport.close();
  demoTransport.close();
  print('DONE');
}

String _upload(String filename, String content) {
  final escaped = content.replaceAll('\\', '\\\\').replaceAll("'''", "\\'\\'\\'");
  return """
import json
soliplex_upload_to_thread("local", "bwrap_sandbox", thread, "$filename", '''$escaped''')
"uploaded $filename"
""";
}

Future<String?> _extract(AgentSession session) async {
  final r = await session.execute(r"""
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
elif "blackboard" in gen_response or "schedule" in gen_response:
    extracted_code = gen_response.strip()
else:
    extracted_code = None
extracted_code
""");
  return r.value?.dartValue as String?;
}
