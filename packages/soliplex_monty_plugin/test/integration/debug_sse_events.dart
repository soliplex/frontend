// Uses print for debug output in manual test scripts.
// ignore_for_file: avoid_print
// Debug SSE event flow — traces every event from the stream
// to find where null returns come from.
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_monty_plugin/soliplex_monty_plugin.dart';

Future<void> main() async {
  // Create a raw connection to trace SSE events directly
  final transport = HttpTransport(client: DartHttpClient());
  final urlBuilder = UrlBuilder('http://localhost:8000/api/v1');
  final api = SoliplexApi(transport: transport, urlBuilder: urlBuilder);
  final streamClient = AgUiStreamClient(
    httpTransport: transport,
    urlBuilder: urlBuilder,
    onWarning: (msg) => print('  WARNING: $msg'),
  );

  // Step 1: Create thread
  print('=== Creating thread ===');
  final (threadInfo, aguiState) = await api.createThread('bwrap_sandbox');
  final threadId = threadInfo.id;
  final runId = threadInfo.initialRunId;
  print('  thread=$threadId run=$runId state=$aguiState');

  // Step 2: Build input
  final input = SimpleRunAgentInput(
    threadId: threadId,
    runId: runId,
    messages: [
      const UserMessage(
        id: 'user_1',
        content: 'Write a short Python hello world',
      ),
    ],
    state: aguiState,
  );

  // Step 3: Stream events and log EVERY one
  print('\n=== Streaming SSE events ===');
  final endpoint = 'rooms/bwrap_sandbox/agui/$threadId/$runId';
  final stream = streamClient.runAgent(endpoint, input);

  final buffer = StringBuffer();
  var eventCount = 0;
  String? lastMessageId;

  await for (final event in stream) {
    eventCount++;
    switch (event) {
      case RunStartedEvent(:final threadId, :final runId):
        print('  [$eventCount] RunStarted thread=$threadId run=$runId');
      case TextMessageStartEvent(:final messageId):
        lastMessageId = messageId;
        print('  [$eventCount] TextMessageStart id=$messageId');
      case TextMessageContentEvent(:final messageId, :final delta):
        buffer.write(delta);
        print(
          '  [$eventCount] TextMessageContent id=$messageId '
          'delta=${delta.length} chars (total=${buffer.length})',
        );
      case TextMessageEndEvent(:final messageId):
        print('  [$eventCount] TextMessageEnd id=$messageId');
      case StateSnapshotEvent(:final snapshot):
        print('  [$eventCount] StateSnapshot keys=${(snapshot as Map?)?.keys}');
      case RunFinishedEvent(:final threadId, :final runId):
        print('  [$eventCount] RunFinished thread=$threadId run=$runId');
      case RunErrorEvent(:final message):
        print('  [$eventCount] RunError: $message');
      default:
        print('  [$eventCount] ${event.runtimeType}');
    }
  }

  print('\n=== Results ===');
  print('  Events: $eventCount');
  print('  Message ID: $lastMessageId');
  print('  Buffer length: ${buffer.length}');
  print(
    '  Response: '
    '${buffer.toString().substring(0, buffer.length.clamp(0, 200))}',
  );

  // Step 4: Now do a SECOND run on same thread (reply)
  print('\n=== Second run (reply) ===');
  final run2 = await api.createRun('bwrap_sandbox', threadId);
  final runId2 = run2.id;
  print('  run2=$runId2');

  final input2 = SimpleRunAgentInput(
    threadId: threadId,
    runId: runId2,
    messages: [
      const UserMessage(
        id: 'user_1',
        content: 'Write a short Python hello world',
      ),
      AssistantMessage(id: lastMessageId ?? 'a_1', content: buffer.toString()),
      const UserMessage(
        id: 'user_2',
        content: 'Now make it print goodbye too',
      ),
    ],
    state: aguiState,
  );

  final endpoint2 = 'rooms/bwrap_sandbox/agui/$threadId/$runId2';
  final stream2 = streamClient.runAgent(endpoint2, input2);
  final buffer2 = StringBuffer();
  var eventCount2 = 0;

  await for (final event in stream2) {
    eventCount2++;
    switch (event) {
      case TextMessageContentEvent(:final delta):
        buffer2.write(delta);
        print('  [$eventCount2] Content: ${delta.length} chars');
      case RunFinishedEvent():
        print('  [$eventCount2] RunFinished');
      case RunErrorEvent(:final message):
        print('  [$eventCount2] ERROR: $message');
      default:
        print('  [$eventCount2] ${event.runtimeType}');
    }
  }

  print('\n=== Reply Results ===');
  print('  Events: $eventCount2');
  print('  Buffer: ${buffer2.length} chars');
  print(
    '  Response: '
    '${buffer2.toString().substring(0, buffer2.length.clamp(0, 200))}',
  );

  // Step 5: Test through buildSoliplexTools
  print('\n=== Through buildSoliplexTools ===');
  final conn = SoliplexConnection(
    serverId: 'local',
    alias: 'local',
    serverUrl: 'http://localhost:8000',
    api: api,
    streamClient: streamClient,
  );
  final tools = buildSoliplexTools(
    const SessionContext(serverId: 'local', roomId: 'bwrap_sandbox'),
    {'local': conn},
  );
  final handler =
      tools.firstWhere((t) => t.name == 'soliplex_new_thread').handler;
  final pluginResult = (await handler({
    'server': 'local',
    'room_id': 'bwrap_sandbox',
    'message': 'Say hello',
  }))! as Map<String, dynamic>;
  print('  thread_id: ${pluginResult['thread_id']}');
  print(
    '  response: '
    '${(pluginResult['response'] as String).substring(0, 100)}',
  );

  transport.close();
  print('\nDONE');
}
