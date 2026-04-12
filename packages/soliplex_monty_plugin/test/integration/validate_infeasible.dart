// ignore_for_file: avoid_print
import 'package:dart_monty/dart_monty_bridge.dart';

Future<void> main() async {
  final session = AgentSession();

  // Test: does monty support % string formatting?
  var r = await session.execute('"hello %s" % "world"');
  print('% format: ${r.value?.dartValue} / ${r.error}');

  // Test: f-string
  r = await session.execute('x = 42\nf"value is {x}"');
  print('f-string: ${r.value?.dartValue} / ${r.error}');

  // Test: string concat
  r = await session.execute('"hello " + str(42)');
  print('concat: ${r.value?.dartValue} / ${r.error}');

  // Now the actual infeasible code
  r = await session.execute(r'''
num_houses = 5
jobs_per_house = 3
total_jobs = num_houses * jobs_per_house
workers = 3
days_deadline = 3
total_worker_days = workers * days_deadline

analysis = {
    "total_jobs": total_jobs,
    "total_worker_days": total_worker_days,
    "max_jobs_per_day": workers,
}

if total_worker_days >= total_jobs:
    status = "feasible"
    reason = "Sufficient worker-days."
else:
    status = "infeasible"
    reason = "Only " + str(total_worker_days) + " slots for " + str(total_jobs) + " jobs."

{"status": status, "reason": reason, "analysis": analysis}
''');

  print('\nResult: ${r.value?.dartValue}');
  if (r.error != null) print('Error: ${r.error}');

  final m = r.value?.dartValue as Map?;
  if (m != null) {
    print('Status: ${m["status"]}');
    print('Reason: ${m["reason"]}');
    print('CORRECT: ${m["status"] == "infeasible" ? "YES ✅" : "NO ❌"}');
  }

  await session.dispose();
}
