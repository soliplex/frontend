// Uses print for debug output in manual test scripts.
// ignore_for_file: avoid_print
import 'package:dart_monty/dart_monty_bridge.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_monty_plugin/soliplex_monty_plugin.dart';

Future<void> main() async {
  final transport = HttpTransport(client: DartHttpClient());
  final urlBuilder = UrlBuilder('http://localhost:8000/api/v1');

  final session = AgentSession(
    plugins: [
      SoliplexPlugin(
        connections: {
          'local': SoliplexConnection(
            api: SoliplexApi(transport: transport, urlBuilder: urlBuilder),
            streamClient: AgUiStreamClient(
              httpTransport: transport,
              urlBuilder: urlBuilder,
            ),
          ),
        },
      ),
    ],
  );

  // Call 1: SSE host function
  print('Call 1: new_thread...');
  final r1 = await session.execute('''
import json
resp = json.loads(soliplex_new_thread("local", "chat", "Hello"))
gen_response = resp["response"]
gen_response
''');
  print('  value: ${r1.value?.dartValue}');
  print('  error: ${r1.error}');
  print('  print: ${r1.printOutput}');

  // Call 2: read persisted state
  print('Call 2: read gen_response...');
  final r2 = await session.execute('gen_response');
  print('  value: ${r2.value?.dartValue}');
  print('  error: ${r2.error}');

  // Call 3: another SSE call
  print('Call 3: another new_thread...');
  final r3 = await session.execute('''
import json
resp2 = json.loads(soliplex_new_thread("local", "chat", "Tell me a joke"))
resp2["response"]
''');
  print('  value: ${r3.value?.dartValue}');
  print('  error: ${r3.error}');

  await session.dispose();
  transport.close();
  print('DONE');
}
