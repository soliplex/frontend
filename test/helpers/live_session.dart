import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
// ignore: implementation_imports
import 'package:soliplex_agent/src/orchestration/run_orchestrator.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show AgUiStreamClient, HttpTransport, SoliplexApi, UrlBuilder;

import 'package:soliplex_frontend/src/modules/room/execution_tracker_extension.dart';

import 'test_logger.dart';

/// Real sessions over scripted AG-UI streams, and real history replayed from
/// stored events: the two paths a thread's contents arrive by, with nothing
/// mocked between the events and what the room reads.

class _MockApi extends Mock implements SoliplexApi {}

class _MockStreamClient extends Mock implements AgUiStreamClient {}

class _MockRuntime extends Mock implements AgentRuntime {}

class _MockHttpTransport extends Mock implements HttpTransport {}

class _FakeInput extends Fake implements SimpleRunAgentInput {}

class _FakeCancelToken extends Fake implements CancelToken {}

/// Call from `setUpAll` in any test that uses [startLiveSession] or
/// [storedHistory].
void registerLiveSessionFallbacks() {
  registerFallbackValue(_FakeInput());
  registerFallbackValue(_FakeCancelToken());
  registerFallbackValue(const (serverId: 'f', roomId: 'f', threadId: 'f'));
  registerFallbackValue(Uri.parse('https://example.com'));
  registerFallbackValue(CancelToken());
}

/// A session running [runId], fed by [events], with its band registry
/// attached as the room attaches one.
typedef LiveSession = ({
  AgentSession session,
  RunOrchestrator orchestrator,
  ExecutionTrackerExtension trackers,
  StreamController<BaseEvent> events,
});

/// Starts a session on [key] whose backend answers with [runId] and then
/// streams whatever is added to `events`. Yield once before adding any.
///
/// [cachedHistory] is the thread as the runtime last loaded it, which a real
/// send builds its conversation on.
LiveSession startLiveSession({
  required ThreadKey key,
  required String runId,
  String prompt = 'Q',
  ThreadHistory? cachedHistory,
}) {
  final api = _MockApi();
  final streamClient = _MockStreamClient();
  final events = StreamController<BaseEvent>();
  when(() => api.createRun(any(), any())).thenAnswer(
    (_) async => RunInfo(
      id: runId,
      threadId: key.threadId,
      createdAt: DateTime.utc(2026),
    ),
  );
  when(
    () => streamClient.runAgent(
      any(),
      any(),
      cancelToken: any(named: 'cancelToken'),
      resumePolicy: any(named: 'resumePolicy'),
      onReconnectStatus: any(named: 'onReconnectStatus'),
    ),
  ).thenAnswer(
    (_) => events.stream.map<DecodeOutcome>((e) => DecodedEvent(e, const {})),
  );

  final orchestrator = RunOrchestrator(
    llmProvider: AgUiLlmProvider(api: api, agUiStreamClient: streamClient),
    toolRegistry: const ToolRegistry(),
    logger: testLogger('orchestrator'),
  );
  final trackers = ExecutionTrackerExtension(logger: testLogger('ext'));
  final runtime = _MockRuntime();
  when(() => runtime.ensureThreadState(any())).thenReturn(ThreadState());
  // Built directly rather than through `AgentRuntime.spawn`: every mock
  // between the events and the room's inputs is fidelity these tests exist to
  // avoid spending.
  // ignore: invalid_use_of_internal_member
  final session = AgentSession(
    threadKey: key,
    ephemeral: false,
    depth: 0,
    runtime: runtime,
    orchestrator: orchestrator,
    toolRegistry: const ToolRegistry(),
    coordinator: SessionCoordinator([trackers], logger: testLogger('coord')),
    logger: testLogger('session'),
  );
  unawaited(
    session
        .start(userMessage: [TextPart(prompt)], cachedHistory: cachedHistory),
  );
  return (
    session: session,
    orchestrator: orchestrator,
    trackers: trackers,
    events: events,
  );
}

/// A run as the backend stores it: its id, the turn's user message — stored
/// as run input under an id the live echo never sees — and its events.
typedef StoredRun = ({
  String runId,
  String userMessageId,
  String prompt,
  List<BaseEvent> events,
});

/// The history the backend serves for [runs], every one of them finished,
/// decoded by the real client.
Future<ThreadHistory> storedHistory(List<StoredRun> runs) async {
  final transport = _MockHttpTransport();
  final api = SoliplexApi(
    transport: transport,
    urlBuilder: UrlBuilder('https://api.example.com/api/v1'),
  );
  addTearDown(api.close);
  when(() => transport.close()).thenReturn(null);

  void stub(String path, Map<String, dynamic> body) {
    when(
      () => transport.request<Map<String, dynamic>>(
        'GET',
        Uri.parse('https://api.example.com/api/v1$path'),
        cancelToken: any(named: 'cancelToken'),
        fromJson: any(named: 'fromJson'),
        body: any(named: 'body'),
        headers: any(named: 'headers'),
        timeout: any(named: 'timeout'),
      ),
    ).thenAnswer((_) async => body);
  }

  stub('/rooms/r/agui/t', {
    'room_id': 'r',
    'thread_id': 't',
    'runs': {
      for (final (index, run) in runs.indexed)
        run.runId: {
          'run_id': run.runId,
          'created': '2026-01-07T01:0$index:00.000Z',
          'finished': '2026-01-07T01:0$index:30.000Z',
        },
    },
  });
  for (final run in runs) {
    stub('/rooms/r/agui/t/${run.runId}', {
      'run_id': run.runId,
      'run_input': {
        'messages': [
          {'role': 'user', 'id': run.userMessageId, 'content': run.prompt},
        ],
      },
      'events': [for (final event in run.events) event.toJson()],
    });
  }

  return api.getThreadHistory('r', 't');
}
