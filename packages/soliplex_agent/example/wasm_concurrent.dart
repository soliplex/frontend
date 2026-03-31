/// Demonstrates concurrent agent sessions on WASM platform constraints.
///
/// Multiple sessions stream HTTP/SSE responses simultaneously. The
/// interpreter bridge (`maxConcurrentBridges: 1`) serializes Python tool
/// execution, but session-level concurrency (`maxConcurrentSessions: 4`)
/// allows HTTP-only sessions to run in parallel.
///
/// ```bash
/// dart run example/wasm_concurrent.dart
/// ```
///
/// Requires a running Soliplex backend at http://localhost:8000.
library;

import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart' show DartHttpClient;
import 'package:soliplex_logging/soliplex_logging.dart';

Future<void> main() async {
  final logManager = LogManager.instance
    ..minimumLevel = LogLevel.info
    ..addSink(StdoutSink(useColors: true));
  final logger = logManager.getLogger('wasm_concurrent');

  final connection = ServerConnection.create(
    serverId: 'default',
    serverUrl: 'http://localhost:8000',
    httpClient: DartHttpClient(),
  );

  // Web platform: maxConcurrentBridges=1, maxConcurrentSessions=4.
  // Sessions stream HTTP concurrently; bridge access is serialized.
  final runtime = AgentRuntime(
    connection: connection,
    llmProvider: AgUiLlmProvider(
      api: connection.api,
      agUiStreamClient: connection.agUiStreamClient,
    ),
    toolRegistryResolver: (_) async => const ToolRegistry(),
    platform: const WebPlatformConstraints(),
    logger: logger,
  );

  try {
    // Spawn 3 concurrent sessions — all HTTP-only, no bridge contention.
    final sessions = await Future.wait([
      runtime.spawn(
        roomId: 'plain',
        prompt: 'What is Dart?',
        autoDispose: true,
      ),
      runtime.spawn(
        roomId: 'plain',
        prompt: 'What is WASM?',
        autoDispose: true,
      ),
      runtime.spawn(
        roomId: 'plain',
        prompt: 'What is AG-UI?',
        autoDispose: true,
      ),
    ]);

    logger.info('Spawned ${sessions.length} concurrent sessions');

    final results = await runtime.waitAll(
      sessions,
      timeout: const Duration(seconds: 30),
    );

    for (final (i, result) in results.indexed) {
      switch (result) {
        case AgentSuccess(:final output):
          logger.info('Session $i: $output');
        case AgentFailure(:final reason):
          logger.error('Session $i failed: $reason');
        case AgentTimedOut():
          logger.warning('Session $i timed out');
      }
    }
  } finally {
    await runtime.dispose();
    await connection.close();
  }
}
