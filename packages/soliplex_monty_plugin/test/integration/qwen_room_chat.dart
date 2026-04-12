// ignore_for_file: avoid_print
/// Two Qwen rooms talking to each other — 8B asks questions, 35B answers
import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:soliplex_monty_plugin/soliplex_monty_plugin.dart';
import 'package:soliplex_client/soliplex_client.dart';

Future<void> main() async {
  final transport = HttpTransport(client: DartHttpClient());
  final localUrl = UrlBuilder('http://localhost:8000/api/v1');

  final session = AgentSession(
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

  print('=== ROOM-TO-ROOM CONVERSATION ===');
  print('8B asks → 35B answers → 8B asks follow-up → 5 rounds\n');

  // Round 1: seed topic on 35B
  var r = await session.execute('''
import json
print("Starting conversation...")
t = json.loads(soliplex_new_thread("local", "qwen_vllm", "Explain what a Python decorator is in 2 sentences."))
thread_35b = t["thread_id"]
answer = t["response"]
print("35B said: " + answer[:300])
answer
''');
  print('--- ROUND 1 ---');
  print('35B: ${_trunc(r.value?.dartValue as String? ?? "null", 300)}\n');

  for (var round = 2; round <= 6; round++) {
    // 8B reads answer, asks follow-up
    r = await session.execute('''
import json
print(f"Round $round: 8B generating question...")
t = json.loads(soliplex_new_thread("local", "qwen_8b", "Someone said: " + answer[:500] + " — Ask ONE short follow-up question."))
question = t["response"]
print("8B asks: " + question[:200])
question
''');
    final question = r.value?.dartValue as String?;
    print('--- ROUND $round ---');
    print('8B asks: ${_trunc(question ?? "null", 200)}');

    if (question == null) {
      print('  (8B returned null — stopping)\n');
      break;
    }

    // 35B answers the follow-up
    r = await session.execute('''
import json
print(f"Round $round: 35B answering...")
t = json.loads(soliplex_reply_thread("local", "qwen_vllm", thread_35b, question[:500]))
answer = t["response"]
print("35B: " + answer[:300])
answer
''');
    final ans = r.value?.dartValue as String?;
    print('35B: ${_trunc(ans ?? "null", 300)}\n');

    if (ans == null) {
      print('  (35B returned null — stopping)\n');
      break;
    }
  }

  print('=== CONVERSATION COMPLETE ===');
  await session.dispose();
  transport.close();
}

String _trunc(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}...';
