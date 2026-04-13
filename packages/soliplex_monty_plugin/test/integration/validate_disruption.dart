// Uses print for debug output in manual test scripts.
// ignore_for_file: avoid_print
import 'package:dart_monty/dart_monty_bridge.dart';

Future<void> main() async {
  final session = AgentSession();
  final result = await session.execute('''
schedule = {}
disruption_list = []
weather = {1:"rain",2:"sunny",3:"sunny",4:"sunny",5:"sunny"}
jobs = {
    "H1_FND": {"role":"concrete_crew","location":"outdoor"},
    "H1_FRM": {"role":"framer","location":"indoor"},
    "H1_ROF": {"role":"roofer","location":"outdoor"},
    "H2_FND": {"role":"concrete_crew","location":"outdoor"},
    "H2_FRM": {"role":"framer","location":"indoor"}
}
deps = {"H1_FRM": ["H1_FND"], "H1_ROF": ["H1_FRM"], "H2_FRM": ["H2_FND"]}
workers = {"Bob":"concrete_crew", "Alice":"framer", "Charlie":"roofer"}
done = set()

for d in range(1,6):
    if d == 2:
        disruption_list.append("day=2 worker=Alice status=sick")
        sick_workers = ["Alice"]
    else:
        sick_workers = []

    avail = {}
    for w, role in workers.items():
        if w not in sick_workers:
            avail[w] = role

    ready = []
    for j, info in jobs.items():
        if j in done:
            continue
        if j in deps and any(dep not in done for dep in deps[j]):
            continue
        if info["location"]=="outdoor" and weather[d]=="rain":
            continue
        ready.append(j)

    assignments = []
    assigned_workers = {}
    for w, role in avail.items():
        for j in ready:
            if jobs[j]["role"]==role and j not in assigned_workers:
                assignments.append({"worker": w, "job": j})
                assigned_workers[j] = w
                break

    schedule[d] = assignments
    for a in assignments:
        done.add(a["job"])

{"executed_schedule": schedule, "disruptions": disruption_list}
''');

  print('Result: ${result.value?.dartValue}');
  if (result.error != null) {
    print('Error: ${result.error}');
    await session.dispose();
    return;
  }

  final r = result.value!.dartValue! as Map;
  final sched = r['executed_schedule'] as Map;
  final disrupt = r['disruptions'] as List;

  print('\nSchedule:');
  for (final e in sched.entries) {
    print('  Day ${e.key}: ${e.value}');
  }
  print('Disruptions: $disrupt');

  // Validate
  final jobDays = <String, int>{};
  for (final e in sched.entries) {
    for (final a in e.value as List) {
      jobDays[(a as Map)['job'] as String] = e.key as int;
    }
  }
  print('\nJob days: $jobDays');

  // Check Alice not assigned on day 2
  final day2 = sched[2] as List;
  final aliceOnDay2 = day2.any((a) => (a as Map)['worker'] == 'Alice');
  print('Alice on day 2: $aliceOnDay2 (should be false)');

  // Check deps
  final depsOk = (jobDays['H1_FND']! < jobDays['H1_FRM']!) &&
      (jobDays['H1_FRM']! < jobDays['H1_ROF']!) &&
      (jobDays['H2_FND']! < jobDays['H2_FRM']!);
  print('Deps valid: $depsOk');

  // No outdoor on rain day 1
  final day1 = sched[1] as List;
  final noRain = day1.isEmpty ||
      !day1.any((a) {
        final j = (a as Map)['job'] as String;
        return j.contains('FND') || j.contains('ROF');
      });
  print('No outdoor rain: $noRain');

  final allDone = jobDays.length == 5;
  print('All done: $allDone');

  final correct = depsOk && !aliceOnDay2 && noRain && allDone;
  print('\nVERDICT: ${correct ? "CORRECT ✅" : "INCORRECT ❌"}');

  await session.dispose();
}
