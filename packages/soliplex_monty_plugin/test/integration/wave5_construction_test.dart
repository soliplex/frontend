// Wave5 construction scheduling — complex multi-step codegen
// ignore_for_file: avoid_print, cast_nullable_to_non_nullable
@Tags(['integration'])
library;

import 'dart:io';

import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_monty_plugin/soliplex_monty_plugin.dart';
import 'package:test/test.dart';

/// Upload wave5 construction experiments to bwrap_sandbox, have the agent
/// generate monty code that solves them using host functions.
///
/// The agent maps:
/// - "blackboard" → msg_send/msg_recv channels + filesystem
/// - "oracle" → soliplex_new_thread to ask the LLM for reasoning
/// - "bb_dump" → write final state to file + return as dict
///
/// Configure via environment variables:
///   SOLIPLEX_DEMO_URL     — cloud server base URL
///   SOLIPLEX_LOCAL_URL    — local server base URL (default: http://localhost:8000)
///   IOI_EXPERIMENTS_DIR   — directory containing wave5 experiment .txt files
///   MONTY_DOCS_DIR        — directory containing monty-prompt-rules.md
///
/// Run:
///   dart test test/integration/wave5_construction_test.dart -t integration --reporter expanded
final String _demoUrl =
    Platform.environment['SOLIPLEX_DEMO_URL'] ?? 'http://localhost:8000';
final String _localUrl =
    Platform.environment['SOLIPLEX_LOCAL_URL'] ?? 'http://localhost:8000';
final String? _ioiDir = Platform.environment['IOI_EXPERIMENTS_DIR'];
final String? _montyDocsDir = Platform.environment['MONTY_DOCS_DIR'];

void main() {
  late AgentSession session;

  setUpAll(() {
    session = AgentSession(
      os: OsProvider.compose({
        'Path.': MemoryFsProvider(),
      }),
      plugins: [
        SoliplexPlugin(
          connections: {
            'demo': _buildConnection(_demoUrl),
            'local': _buildConnection(_localUrl),
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

  test(
    '1. Upload ruleset + baseline experiment',
    () async {
      if (_ioiDir == null || _montyDocsDir == null) {
        markTestSkipped(
          'Set IOI_EXPERIMENTS_DIR and MONTY_DOCS_DIR to run file-based tests',
        );
        return;
      }
      // Read the experiment files
      final baseline = File(
        '$_ioiDir/wave5-construction-baseline.txt',
      ).readAsStringSync();

      final rules = File(
        '$_montyDocsDir/monty-prompt-rules.md',
      ).readAsStringSync();

      // Create thread and upload files
      final r = await session.execute('''
import json

t = json.loads(soliplex_new_thread("local", "bwrap_sandbox", "I will upload experiment files."))
wave5_thread = t["thread_id"]
wave5_thread
''');
      print('  Thread: ${r.value?.dartValue}');

      await session.execute('''
import json
soliplex_upload_to_thread("local", "bwrap_sandbox", wave5_thread, "monty-rules.md", ${_pyStr(rules)})
"rules uploaded"
''');
      print('  Rules uploaded');

      await session.execute('''
import json
soliplex_upload_to_thread("local", "bwrap_sandbox", wave5_thread, "baseline-experiment.txt", ${_pyStr(baseline)})
"baseline uploaded"
''');
      print('  Baseline uploaded');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    '2. Ask agent to solve baseline scheduling',
    () async {
      final gen = await session.execute('''
import json
resp = json.loads(soliplex_reply_thread(
    "local", "bwrap_sandbox", wave5_thread,
    "Read monty-rules.md for the coding rules. "
    "Read baseline-experiment.txt for the problem. "
    "Write a monty program that solves the construction scheduling problem. "
    "Map the concepts: "
    "- Use a Python dict as the blackboard (not msg_send) "
    "- Use soliplex_new_thread to ask the demo cooking room as the oracle for confirmation "
    "- Track jobs, dependencies, weather, and worker assignments "
    "- The last expression should be the final schedule dict "
    "Return ONLY code in a ```monty``` block."
))
gen_response = resp["response"]
gen_response
''');
      if (gen.value?.dartValue == null) {
        print('  null response — server may be slow');

        return;
      }
      print('  Agent response (${(gen.value!.dartValue as String).length}'
          ' chars):');
      print('  ${_trunc(gen.value!.dartValue as String, 300)}');

      // Extract code
      final code = await _extractCode(session);
      if (code == null) {
        print('  No code block extracted');

        return;
      }
      print('  Code (${code.length} chars):');
      print('  ${_trunc(code, 300)}');

      // Execute
      final result = await session.execute(code);
      if (result.error != null) {
        print('  Error: ${result.error}');
      }
      print('  Result: ${result.value?.dartValue}');
      if (result.printOutput != null && result.printOutput!.isNotEmpty) {
        print('  Print output:');
        print(
          '  ${result.printOutput!.split('\n').take(10).join('\n  ')}',
        );
      }
    },
    timeout: const Timeout(Duration(seconds: 180)),
  );

  test(
    '3. Upload and solve schedule optimization',
    () async {
      if (_ioiDir == null) {
        markTestSkipped('Set IOI_EXPERIMENTS_DIR to run file-based tests');
        return;
      }
      final schedule = File(
        '$_ioiDir/wave5-construction-schedule.txt',
      ).readAsStringSync();

      await session.execute('''
import json
soliplex_upload_to_thread("local", "bwrap_sandbox", wave5_thread, "schedule-experiment.txt", ${_pyStr(schedule)})
"schedule uploaded"
''');

      final gen = await session.execute('''
import json
resp = json.loads(soliplex_reply_thread(
    "local", "bwrap_sandbox", wave5_thread,
    "Now read schedule-experiment.txt. This is an OPTIMIZATION problem — "
    "find the schedule that finishes ALL jobs as early as possible. "
    "Write monty code that solves it. Use a dict as blackboard. "
    "Return ONLY code in a ```monty``` block."
))
gen_response = resp["response"]
gen_response
''');
      if (gen.value?.dartValue == null) {
        print('  null — skipping');

        return;
      }
      print('  ${_trunc(gen.value!.dartValue as String, 200)}');

      final code = await _extractCode(session);
      if (code == null) return;

      final result = await session.execute(code);
      print('  Result: ${result.value?.dartValue}');
      if (result.printOutput?.isNotEmpty ?? false) {
        print('  Output: ${_trunc(result.printOutput!, 200)}');
      }
    },
    timeout: const Timeout(Duration(seconds: 180)),
  );

  test(
    '4. Upload and solve disruption scenario',
    () async {
      if (_ioiDir == null) {
        markTestSkipped('Set IOI_EXPERIMENTS_DIR to run file-based tests');
        return;
      }
      final disruption = File(
        '$_ioiDir/wave5-construction-disruption.txt',
      ).readAsStringSync();

      await session.execute('''
import json
soliplex_upload_to_thread("local", "bwrap_sandbox", wave5_thread, "disruption-experiment.txt", ${_pyStr(disruption)})
"disruption uploaded"
''');

      final gen = await session.execute('''
import json
resp = json.loads(soliplex_reply_thread(
    "local", "bwrap_sandbox", wave5_thread,
    "Now read disruption-experiment.txt. This scenario has DISRUPTIONS — "
    "Alice calls in sick on day 2. Simulate day by day, adjusting the schedule. "
    "Write monty code. Use a dict as blackboard. "
    "Return ONLY code in a ```monty``` block."
))
gen_response = resp["response"]
gen_response
''');
      if (gen.value?.dartValue == null) {
        print('  null — skipping');

        return;
      }
      print('  ${_trunc(gen.value!.dartValue as String, 200)}');

      final code = await _extractCode(session);
      if (code == null) return;

      final result = await session.execute(code);
      print('  Result: ${result.value?.dartValue}');
    },
    timeout: const Timeout(Duration(seconds: 180)),
  );

  test(
    '5. Upload and analyze infeasible scenario',
    () async {
      if (_ioiDir == null) {
        markTestSkipped('Set IOI_EXPERIMENTS_DIR to run file-based tests');
        return;
      }
      final infeasible = File(
        '$_ioiDir/wave5-construction-infeasible.txt',
      ).readAsStringSync();

      await session.execute('''
import json
soliplex_upload_to_thread("local", "bwrap_sandbox", wave5_thread, "infeasible-experiment.txt", ${_pyStr(infeasible)})
"infeasible uploaded"
''');

      final gen = await session.execute('''
import json
resp = json.loads(soliplex_reply_thread(
    "local", "bwrap_sandbox", wave5_thread,
    "Now read infeasible-experiment.txt. This is 5 houses × 3 jobs = 15 jobs "
    "with only 3 workers and a 3-day deadline. Analyze feasibility. "
    "Write monty code that determines if the schedule is feasible and why/why not. "
    "Return ONLY code in a ```monty``` block."
))
gen_response = resp["response"]
gen_response
''');
      if (gen.value?.dartValue == null) {
        print('  null — skipping');

        return;
      }
      print('  ${_trunc(gen.value!.dartValue as String, 200)}');

      final code = await _extractCode(session);
      if (code == null) return;

      final result = await session.execute(code);
      print('  Result: ${result.value?.dartValue}');
    },
    timeout: const Timeout(Duration(seconds: 180)),
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
elif "import json" in gen_response or "blackboard" in gen_response:
    extracted_code = gen_response.strip()
else:
    extracted_code = None
extracted_code
''');

  return r.value?.dartValue as String?;
}

String _trunc(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}...';

String _pyStr(String s) {
  // Triple-quote Python string with escapes
  final escaped = s.replaceAll(r'\', r'\\').replaceAll('"""', r'\"\"\"');

  return '"""$escaped"""';
}
