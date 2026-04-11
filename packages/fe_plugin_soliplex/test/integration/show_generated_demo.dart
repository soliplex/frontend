// ignore_for_file: avoid_print
/// Use demo.toughserv.com (GPT-4o) to generate code for each experiment.
/// Embeds the full prompt inline — no file upload needed.
import 'dart:io';

import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:fe_plugin_soliplex/fe_plugin_soliplex.dart';
import 'package:soliplex_client/soliplex_client.dart';

Future<void> main() async {
  final transport = HttpTransport(client: DartHttpClient());
  final demoUrl = UrlBuilder('https://demo.toughserv.com/api/v1');

  final rules = File(
    '/Users/runyaga/dev/dart_monty/main/docs/monty-prompt-rules.md',
  ).readAsStringSync();

  const expDir =
      '/Users/runyaga/dev/soliplex-plans/tui-experiments/ioi-experiments';

  final experiments = [
    ('BASELINE', File('$expDir/wave5-construction-baseline.txt').readAsStringSync()),
    ('OPTIMAL SCHEDULE', File('$expDir/wave5-construction-schedule.txt').readAsStringSync()),
    ('DISRUPTION', File('$expDir/wave5-construction-disruption.txt').readAsStringSync()),
    ('INFEASIBLE', File('$expDir/wave5-construction-infeasible.txt').readAsStringSync()),
  ];

  for (final (name, expText) in experiments) {
    print('${"=" * 70}');
    print('EXPERIMENT: $name');
    print('${"=" * 70}\n');

    final session = AgentSession(
      os: OsProvider.compose({'Path.': MemoryFsProvider()}),
      plugins: [
        SoliplexPlugin(
          connections: {
            'demo': SoliplexConnection(
              api: SoliplexApi(transport: transport, urlBuilder: demoUrl),
              streamClient: AgUiStreamClient(
                httpTransport: transport,
                urlBuilder: demoUrl,
              ),
            ),
          },
        ),
      ],
    );

    // Combine rules + experiment into one prompt
    final prompt = '''
$rules

---

# EXPERIMENT

$expText

---

# YOUR TASK

Write a monty program that solves the above experiment.
Follow ALL rules from the monty rules document above exactly.
The last expression must be the result dict.
Return ONLY code in a ```monty``` code block. No explanation outside it.
''';

    // Ask demo chat room (GPT-4o)
    var r = await session.execute('''
import json
resp = json.loads(soliplex_new_thread("demo", "chat", ${_pyTriple(prompt)}))
gen_response = resp["response"]
gen_response
''');

    if (r.value?.dartValue == null) {
      print('  NULL response\n');
      await session.dispose();
      continue;
    }

    final genText = r.value!.dartValue as String;

    // Extract code
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
    code = gen_response.strip() if ("schedule" in gen_response or "status" in gen_response) else None
code
''');

    final code = r.value?.dartValue as String?;
    if (code == null) {
      print('RAW RESPONSE (no code block found):');
      print(genText.substring(0, genText.length.clamp(0, 500)));
      print('\n');
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
      final err = result.error!;
      print('EXECUTION ERROR:');
      print('  Type: ${err.excType}');
      print('  Message: ${err.message}');
      if (err.lineNumber != null) print('  Line: ${err.lineNumber}');
      if (err.sourceCode != null) print('  Source: ${err.sourceCode}');
      if (err.traceback.isNotEmpty) {
        print('  Traceback:');
        for (final frame in err.traceback) {
          print('    $frame');
        }
      }
      print('');
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

String _pyTriple(String s) {
  final escaped = s
      .replaceAll('\\', '\\\\')
      .replaceAll('"""', r'\"\"\"');

  return '"""$escaped"""';
}
