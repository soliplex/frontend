import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
// ignore: implementation_imports
import 'package:soliplex_agent/src/orchestration/run_orchestrator.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show AgUiStreamClient, HttpTransport, SoliplexApi, UrlBuilder;

import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/execution_tracker_extension.dart';
import 'package:soliplex_frontend/src/modules/room/historical_replay.dart';
import 'package:soliplex_frontend/src/modules/room/run_id_resolver.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/timeline_entry.dart';

import '../../helpers/test_logger.dart';

/// One event sequence, both paths, compared at the inputs to `layOutTimeline`.
///
/// `layOutTimeline` is shared, so anything it decides is decided once. What is
/// not shared is what reaches it: live, an orchestrator accumulating a
/// conversation while a tracker registry keys bands off streaming states;
/// reloaded, a replay of stored events into a `ThreadHistory` while
/// `replayToTrackers` buckets the same events by shape. Those are one rule
/// written twice against different inputs, and the seam between them is where
/// a thread renders one way live and another way after a refresh.
///
/// Narrow on purpose: the message list, the band map and the parked outcomes.
/// There is nothing else left that can diverge.

class _MockApi extends Mock implements SoliplexApi {}

class _MockStreamClient extends Mock implements AgUiStreamClient {}

class _MockRuntime extends Mock implements AgentRuntime {}

class _MockHttpTransport extends Mock implements HttpTransport {}

class _FakeInput extends Fake implements SimpleRunAgentInput {}

class _FakeCancelToken extends Fake implements CancelToken {}

const _key = (serverId: 's', roomId: 'r', threadId: 't');
const _runId = 'run-abc';
const _storedUserMessageId = 'u-stored';

/// What reaches `layOutTimeline`, from whichever path produced it.
typedef _Inputs = ({
  List<ChatMessage> messages,
  Map<String, MessageState> messageStates,
  Map<String, ExecutionTracker> bands,
  Map<String, NoResponseTile> outcomes,
});

Future<_Inputs> _live(List<BaseEvent> sequence) async {
  final api = _MockApi();
  final streamClient = _MockStreamClient();
  final events = StreamController<BaseEvent>();
  when(() => api.createRun(any(), any())).thenAnswer(
    (_) async => RunInfo(
      id: _runId,
      threadId: 't',
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
  final ext = ExecutionTrackerExtension(logger: testLogger('ext'));
  final runtime = _MockRuntime();
  when(() => runtime.ensureThreadState(any())).thenReturn(ThreadState());
  // Built directly rather than through `AgentRuntime.spawn`, as the derived
  // timeline integration test does: every mock between the events and the
  // inputs is fidelity this test exists to avoid spending.
  // ignore: invalid_use_of_internal_member
  final session = AgentSession(
    threadKey: _key,
    ephemeral: false,
    depth: 0,
    runtime: runtime,
    orchestrator: orchestrator,
    toolRegistry: const ToolRegistry(),
    coordinator: SessionCoordinator([ext], logger: testLogger('coord')),
    logger: testLogger('session'),
  );

  unawaited(session.start(userMessage: [const TextPart('Q')]));
  await Future<void>.delayed(Duration.zero);
  for (final event in sequence) {
    events.add(event);
    await Future<void>.delayed(Duration.zero);
  }
  await events.close();
  await Future<void>.delayed(Duration.zero);

  final conversation = switch (orchestrator.currentState) {
    CompletedState(:final conversation) => conversation,
    FailedState(:final conversation) => conversation,
    CancelledState(:final conversation) => conversation,
    RunningState(:final conversation) => conversation,
    _ => null,
  };
  orchestrator.dispose();
  expect(conversation, isNotNull, reason: 'the live run reached no terminal');

  return (
    messages: conversation!.messages,
    messageStates: conversation.messageStates,
    bands: ext.trackers,
    outcomes: conversation.runOutcomes,
  );
}

Future<_Inputs> _reloaded(List<BaseEvent> sequence) async {
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
      _runId: {
        'run_id': _runId,
        'created': '2026-01-07T01:00:00.000Z',
        'finished': '2026-01-07T01:01:00.000Z',
      },
    },
  });
  // The backend stores the turn's user message as run input, not as text
  // events — so it reaches replay with an id the live path never sees.
  stub('/rooms/r/agui/t/$_runId', {
    'run_id': _runId,
    'run_input': {
      'messages': [
        {'role': 'user', 'id': _storedUserMessageId, 'content': 'Q'},
      ],
    },
    'events': [for (final event in sequence) event.toJson()],
  });

  final history = await api.getThreadHistory('r', 't');
  return (
    messages: history.messages,
    messageStates: history.messageStates,
    bands: replayToTrackers(history.runs),
    outcomes: history.runOutcomes,
  );
}

/// The band's content, so two trackers built by different code are compared by
/// what they would render rather than by identity.
String _contentOf(ExecutionTracker band) {
  final steps = [
    for (final entry in band.timeline.value)
      switch (entry) {
        TimelineStep(:final step, :final toolCallId, :final result) =>
          '${step.type}/${step.status}/${step.label}'
              '/tool=$toolCallId/result=$result',
        TimelineStandaloneActivity(:final activityId) => 'activity/$activityId',
      },
  ];
  final thinking =
      band.thinkingBlocks.value.where((b) => b.trim().isNotEmpty).toList();
  return 'steps=$steps thinking=$thinking';
}

Future<void> _expectParity(List<BaseEvent> sequence) async {
  final live = await _live(sequence);
  final reloaded = await _reloaded(sequence);

  expect(
    reloaded.messages.map((m) => m.runtimeType).toList(),
    equals(live.messages.map((m) => m.runtimeType).toList()),
    reason: 'the two paths commit a different set of messages',
  );

  for (var i = 0; i < live.messages.length; i++) {
    final l = live.messages[i];
    final r = reloaded.messages[i];
    final where = 'message $i';

    // The turn's own user message is the one exemption, and only in its id:
    // the optimistic echo is minted before the run that carries it, so it
    // cannot know the id the backend will store. Everything a tile renders
    // from, and the run its actions reach, still has to agree.
    final isTurnEcho = l is TextMessage && l.user == ChatUser.user;
    if (!isTurnEcho) expect(r.id, equals(l.id), reason: where);

    expect(r.runId, equals(l.runId), reason: where);
    expect(
      resolveRunId(r, reloaded.messageStates),
      equals(resolveRunId(l, live.messageStates)),
      reason: '$where: the run this tile\'s actions reach',
    );
    if (l is TextMessage) {
      r as TextMessage;
      expect(r.user, equals(l.user), reason: where);
      expect(r.text, equals(l.text), reason: where);
      expect(r.thinkingText, equals(l.thinkingText), reason: where);
      expect(r.namedByToolCall, equals(l.namedByToolCall), reason: where);
    }
  }

  expect(
    reloaded.bands.keys.toSet(),
    equals(live.bands.keys.toSet()),
    reason: 'the two paths key the execution bands differently, so a band '
        'that reaches its tile live reaches nothing after a refresh',
  );
  for (final key in live.bands.keys) {
    expect(
      _contentOf(reloaded.bands[key]!),
      equals(_contentOf(live.bands[key]!)),
      reason: 'band $key',
    );
  }

  expect(
    reloaded.outcomes.keys.toList(),
    equals(live.outcomes.keys.toList()),
    reason: 'the two paths record a different set of runs as ended',
  );
  for (final MapEntry(key: runId, value: l) in live.outcomes.entries) {
    final r = reloaded.outcomes[runId]!;
    expect(r.id, equals(l.id), reason: 'outcome $runId');
    expect(r.runId, equals(l.runId), reason: 'outcome $runId');
    expect(r.reason, equals(l.reason), reason: 'outcome $runId');
    expect(r.thinkingText, equals(l.thinkingText), reason: 'outcome $runId');
    expect(r.errorDetail, equals(l.errorDetail), reason: 'outcome $runId');
  }
}

List<BaseEvent> _reasoning(String id, String delta) => [
      ReasoningMessageStartEvent(messageId: id),
      ReasoningMessageContentEvent(messageId: id, delta: delta),
      ReasoningMessageEndEvent(messageId: id),
    ];

/// A message opened only to give a tool call's `parentMessageId` a target.
List<BaseEvent> _declares(String messageId, String toolCallId) => [
      TextMessageStartEvent(messageId: messageId),
      TextMessageEndEvent(messageId: messageId),
      ToolCallStartEvent(
        toolCallId: toolCallId,
        toolCallName: 'search',
        parentMessageId: messageId,
      ),
      ToolCallEndEvent(toolCallId: toolCallId),
      ToolCallResultEvent(
        messageId: 'tr-$toolCallId',
        toolCallId: toolCallId,
        content: 'ok',
      ),
    ];

/// A tool call and its result — the boundary between two model responses.
List<BaseEvent> _call(String toolCallId) => [
      ToolCallStartEvent(toolCallId: toolCallId, toolCallName: 'search'),
      ToolCallEndEvent(toolCallId: toolCallId),
      ToolCallResultEvent(
        messageId: 'tr-$toolCallId',
        toolCallId: toolCallId,
        content: 'ok',
      ),
    ];

List<BaseEvent> _says(String messageId, String text) => [
      TextMessageStartEvent(messageId: messageId),
      TextMessageContentEvent(messageId: messageId, delta: text),
      TextMessageEndEvent(messageId: messageId),
    ];

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeInput());
    registerFallbackValue(_FakeCancelToken());
    registerFallbackValue(const (serverId: 'f', roomId: 'f', threadId: 'f'));
    registerFallbackValue(Uri.parse('https://example.com'));
    registerFallbackValue(CancelToken());
  });

  test('a run that thinks, declares a tool call, then answers', () async {
    await _expectParity([
      RunStartedEvent(threadId: 't', runId: _runId),
      ..._reasoning('r1', 'weighing it'),
      ..._declares('m1', 'c1'),
      ..._says('m2', 'Answer.'),
      RunFinishedEvent(threadId: 't', runId: _runId),
    ]);
  });

  test('a run that declares a tool call and then says nothing', () async {
    // The shape with no committed tile of its own: what the user watched is
    // held by the band, and where the band lands is decided by the parked
    // outcome. Both sides of that have to be produced identically.
    await _expectParity([
      RunStartedEvent(threadId: 't', runId: _runId),
      ..._reasoning('r1', 'weighing it'),
      ..._declares('m1', 'c1'),
      RunFinishedEvent(threadId: 't', runId: _runId),
    ]);
  });

  test('a run that speaks, works, then answers', () async {
    // Two replies in one run, so the band closes once mid-run and once at the
    // terminal. The first stretch did finish its work — the run moved on to
    // another reply — and must not be reported as unfinished on either path.
    await _expectParity([
      RunStartedEvent(threadId: 't', runId: _runId),
      ..._reasoning('r1', 'let me look'),
      ..._says('m1', 'Let me look that up.'),
      ..._declares('m2', 'c1'),
      ..._reasoning('r2', 'now I have enough'),
      ..._says('m3', 'Below 2,000 ft AGL.'),
      RunFinishedEvent(threadId: 't', runId: _runId),
    ]);
  });

  test('each reply carries the work of the response it was emitted in',
      () async {
    // The producer emits one response at a time: reasoning, then a message,
    // then the tool calls that message asked for. A tool result ends the
    // response, because the model is invoked again to produce the next one.
    // Each reply must therefore carry its own response's work — not the work
    // of the response that follows it.
    await _expectParity([
      RunStartedEvent(threadId: 't', runId: _runId),
      ..._reasoning('r1', 'start with the manual'),
      ..._says('m1', 'Let me check the manual.'),
      ..._call('c1'),
      ..._reasoning('r2', 'now the shutdown procedure'),
      ..._says('m2', 'Now the shutdown procedure.'),
      ..._call('c2'),
      ..._reasoning('r3', 'enough to answer'),
      ..._says('m3', 'Off below 2,000 ft AGL.'),
      RunFinishedEvent(threadId: 't', runId: _runId),
    ]);

    // Parity alone would pass with both paths wrong in the same way, which is
    // how this went unnoticed. Pin the attribution itself.
    final live = await _live([
      RunStartedEvent(threadId: 't', runId: _runId),
      ..._reasoning('r1', 'start with the manual'),
      ..._says('m1', 'Let me check the manual.'),
      ..._call('c1'),
      ..._reasoning('r2', 'now the shutdown procedure'),
      ..._says('m2', 'Now the shutdown procedure.'),
      ..._call('c2'),
      ..._reasoning('r3', 'enough to answer'),
      ..._says('m3', 'Off below 2,000 ft AGL.'),
      RunFinishedEvent(threadId: 't', runId: _runId),
    ]);
    expect(
      live.bands['m1']!.thinkingBlocks.value,
      equals(['start with the manual']),
      reason: 'the first reply carries only its own response',
    );
    expect(
      live.bands['m2']!.thinkingBlocks.value,
      equals(['now the shutdown procedure']),
    );
    expect(
      live.bands['m3']!.thinkingBlocks.value,
      equals(['enough to answer']),
      reason: 'the answer carries the reasoning that produced it',
    );
  });

  test('a declaration whose content event carries only whitespace', () async {
    // Both paths decide whether a message spoke, and so whether it takes the
    // band, from the same rule: content that is only whitespace has not
    // spoken. They hold that rule in two different files.
    await _expectParity([
      RunStartedEvent(threadId: 't', runId: _runId),
      ..._reasoning('r1', 'weighing it'),
      const TextMessageStartEvent(messageId: 'm1'),
      const TextMessageContentEvent(messageId: 'm1', delta: '  '),
      const TextMessageEndEvent(messageId: 'm1'),
      const ToolCallStartEvent(
        toolCallId: 'c1',
        toolCallName: 'search',
        parentMessageId: 'm1',
      ),
      const ToolCallEndEvent(toolCallId: 'c1'),
      const ToolCallResultEvent(
        messageId: 'tr-c1',
        toolCallId: 'c1',
        content: 'ok',
      ),
      ..._says('m2', 'Answer.'),
      RunFinishedEvent(threadId: 't', runId: _runId),
    ]);
  });

  test('a run that fails with a tool call still open', () async {
    // The step is still active when the run ends, so how it settles is decided
    // by the band closing rather than by any event that settles it first.
    await _expectParity([
      RunStartedEvent(threadId: 't', runId: _runId),
      ..._reasoning('r1', 'weighing it'),
      const TextMessageStartEvent(messageId: 'm1'),
      const TextMessageEndEvent(messageId: 'm1'),
      const ToolCallStartEvent(
        toolCallId: 'c1',
        toolCallName: 'search',
        parentMessageId: 'm1',
      ),
      const ToolCallEndEvent(toolCallId: 'c1'),
      const RunErrorEvent(message: 'upstream said no'),
    ]);
  });

  test('a run that fails after its tool call returned', () async {
    // The failure detail is parked, never committed as a message, so the two
    // paths have to record it identically or a reloaded thread loses why the
    // run failed.
    await _expectParity([
      RunStartedEvent(threadId: 't', runId: _runId),
      ..._reasoning('r1', 'weighing it'),
      ..._declares('m1', 'c1'),
      const RunErrorEvent(message: 'upstream said no'),
    ]);
  });
}
