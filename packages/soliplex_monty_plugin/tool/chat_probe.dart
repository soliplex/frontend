// Quick probe: test tool visibility and callbacks in the 'chat' room.
// Run from the plugin directory with: dart run tool/chat_probe.dart
// ignore_for_file: avoid_print
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _logger = LogManager.instance.getLogger('chat_probe');

Future<String> _secretNumber(ToolCallInfo _, ToolExecutionContext __) async =>
    '42';

Future<void> main() async {
  const url = 'https://demo.toughserv.com';

  final conn = ServerConnection.create(
    serverId: 'demo',
    serverUrl: url,
    httpClient: createAgentHttpClient(),
  );

  const secretTool = ClientTool(
    definition: Tool(
      name: 'secret_number',
      description: 'Returns the secret number. '
          'You must call this to answer questions about the secret number.',
      parameters: {'type': 'object', 'properties': <String, Object>{}},
    ),
    executor: _secretNumber,
  );

  final runtime = AgentRuntime(
    connection: conn,
    toolRegistryResolver: (_) async =>
        const ToolRegistry().register(secretTool),
    platform: const WebPlatformConstraints(),
    logger: _logger,
  );

  Future<String> ask(String prompt) async {
    print('\n[PROMPT] $prompt');
    final session = await runtime.spawn(
      roomId: 'chat',
      prompt: prompt,
      ephemeral: true,
      autoDispose: true,
    );
    final result = await session.awaitResult(
      timeout: const Duration(seconds: 60),
    );
    final output = switch (result) {
      AgentSuccess(:final output) => output,
      final r => 'ERROR: $r',
    };
    print('[REPLY ] $output');
    return output;
  }

  try {
    await ask('What tools do you have access to? List only the tool names.');
    await ask(
      'What is the secret number? '
      'You must call the secret_number tool to find out.',
    );
  } finally {
    await runtime.dispose();
  }
}
