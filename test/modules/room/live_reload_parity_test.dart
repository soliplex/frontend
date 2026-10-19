import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/execution_bands.dart';
import 'package:soliplex_frontend/src/modules/room/execution_step.dart';
import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/lay_out_timeline.dart';
import 'package:soliplex_frontend/src/modules/room/run_id_resolver.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/timeline_entry.dart';

import '../../helpers/band_content.dart';
import '../../helpers/live_session.dart';

/// One event sequence, both paths, compared at the inputs to `layOutTimeline`.
///
/// `layOutTimeline` is shared, so anything it decides is decided once, and so
/// are the fold of a run's events and the tracker registry keying its bands.
/// What is not shared is where a run's fold steps come from: live, the
/// orchestrator folding the stream; reloaded, history replay folding the stored
/// events. For the same events both tell `ExecutionBands` the same calls in the
/// same order, except a client-tool wait that ended without resuming, which
/// only live sees; so the seam is each path's source of steps, and the clock.
///
/// Narrow on purpose: the message list, the band map and the parked outcomes.
/// There is nothing else left that can diverge.

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

/// The timeline as the room screen would lay it out in [state], or null when
/// there is no run to show yet.
TimelineLayout? _layOutNow(
  RunState state,
  Map<String, ExecutionTracker> bands,
) {
  final (conversation, streaming, activeRunId) = switch (state) {
    RunningState(:final conversation, :final streaming, :final runId) => (
        conversation,
        streaming,
        runId,
      ),
    CompletedState(:final conversation) => (conversation, null, null),
    FailedState(:final conversation?) => (conversation, null, null),
    CancelledState(:final conversation?) => (conversation, null, null),
    _ => (null, null, null),
  };
  if (conversation == null) return null;
  return layOutTimeline(
    messages: conversation.messages,
    bands: bands,
    outcomes: conversation.runOutcomes,
    streaming: streaming,
    activeRunId: activeRunId,
  );
}

/// Checks every layout of a live run, one event at a time, for what a user
/// watching it would see go wrong.
///
/// Final states are pinned elsewhere; this is the only check on what happens
/// between them, where a band can leave a reply and come back while every end
/// state stays correct.
class _BandWatch {
  /// The tile each band, by identity, first rested on other than the loading
  /// tile. The loading tile stands in for a reply that has not spoken yet, so a
  /// band may leave it; from anywhere else, moving is the band visibly jumping.
  final Map<ExecutionTracker, String> _restedOn = {};

  void check(TimelineLayout? layout, String when) {
    if (layout == null) return;
    expect(layout.dropped, isEmpty, reason: '$when: bands dropped');
    final tileOf = {
      for (final (:message, :band, besideReply: _) in layout.tiles)
        if (band != null) band: message,
    };
    for (final MapEntry(key: band, value: tile) in tileOf.entries) {
      if (!band.hasWork) continue;
      expect(
        tile.runId,
        equals(_runId),
        reason: '$when: a band with work is on tile ${tile.id} of another run',
      );
    }
    for (final MapEntry(key: band, value: restedOn) in _restedOn.entries) {
      expect(
        tileOf[band]?.id,
        equals(restedOn),
        reason: '$when: a band that was on tile $restedOn left it',
      );
    }
    for (final MapEntry(key: band, value: tile) in tileOf.entries) {
      if (tile is LoadingMessage) continue;
      _restedOn.putIfAbsent(band, () => tile.id);
    }
  }
}

Future<_Inputs> _live(List<BaseEvent> sequence, {bool burst = false}) async {
  final (session: _, :orchestrator, trackers: ext, :events, sent: _) =
      startLiveSession(key: _key, runId: _runId);
  final watch = _BandWatch();
  await Future<void>.delayed(Duration.zero);
  for (final (index, event) in sequence.indexed) {
    events.add(event.toJson());
    // A real stream does not pause between events. Yielding after each one
    // hides anything that depends on them arriving one at a time.
    if (burst) continue;
    await Future<void>.delayed(Duration.zero);
    watch.check(
      _layOutNow(orchestrator.currentState, ext.trackers),
      'after event $index (${event.runtimeType})',
    );
  }
  await events.close();
  await Future<void>.delayed(Duration.zero);
  if (!burst) {
    watch.check(
      _layOutNow(orchestrator.currentState, ext.trackers),
      'after the stream closed',
    );
  }

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
  final replay = ExecutionBands.replayed();
  final history = await storedHistory(observer: replay, [
    (
      runId: _runId,
      userMessageId: _storedUserMessageId,
      prompt: 'Q',
      events: sequence,
    ),
  ]);
  return (
    messages: history.messages,
    messageStates: history.messageStates,
    bands: replay.finish(),
    outcomes: history.runOutcomes,
  );
}

List<String> _thinkingOf(ExecutionTracker band) =>
    band.thinkingBlocks.value.where((b) => b.trim().isNotEmpty).toList();

/// Every band that has something to show reaches a tile.
///
/// Parity alone cannot see this: two paths that both drop a band agree.
void _expectEveryBandPlaced(String path, _Inputs inputs) {
  final tiles = layOutTimeline(
    messages: inputs.messages,
    bands: inputs.bands,
    outcomes: inputs.outcomes,
    streaming: null,
    activeRunId: null,
  ).tiles;
  final placed = {
    for (final tile in tiles)
      if (tile.band case final band?) band,
  };
  for (final MapEntry(key: key, value: band) in inputs.bands.entries) {
    if (!band.hasWork) continue;
    expect(
      placed.contains(band),
      isTrue,
      reason: '$path: band $key has work to show and renders nowhere',
    );
  }
}

Future<void> _expectParity(List<BaseEvent> sequence) async =>
    _expectSameInputs(await _live(sequence), await _reloaded(sequence));

/// Expects [live] and [reloaded] to reach `layOutTimeline` alike.
void _expectSameInputs(_Inputs live, _Inputs reloaded) {
  _expectEveryBandPlaced('live', live);
  _expectEveryBandPlaced('reloaded', reloaded);

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
  expect(describeBands(reloaded.bands), describeBands(live.bands));

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

/// A turn whose first run streams [beforeTheCall], then waits on the client
/// tool `locate`, and [continues] as the run that resumes it: live, and
/// reloaded from what live sent.
Future<({_Inputs live, _Inputs reloaded})> _clientToolTurn(
  List<BaseEvent> beforeTheCall,
  List<BaseEvent> continues,
) async {
  final waits = <BaseEvent>[
    RunStartedEvent(threadId: 't', runId: 'run-waits'),
    ...beforeTheCall,
    const ToolCallStartEvent(toolCallId: 'c1', toolCallName: 'locate'),
    const ToolCallArgsEvent(toolCallId: 'c1', delta: '{}'),
    const ToolCallEndEvent(toolCallId: 'c1'),
    const RunFinishedEvent(threadId: 't', runId: 'run-waits'),
  ];
  final session = startLiveSession(
    key: _key,
    runId: 'run-waits',
    toolRegistry: const ToolRegistry().register(
      ClientTool(
        definition: const Tool(name: 'locate', description: 'Locates'),
        executor: (_, __) async => 'Paris',
      ),
    ),
    laterRuns: [
      (
        runId: 'run-continues',
        events: [for (final event in continues) event.toJson()],
      ),
    ],
  );
  await Future<void>.delayed(Duration.zero);
  for (final event in waits) {
    session.events.add(event.toJson());
  }
  await session.events.close();
  await session.session.result;
  final conversation = switch (session.orchestrator.currentState) {
    CompletedState(:final conversation) ||
    FailedState(:final conversation?) =>
      conversation,
    final state => fail('expected the turn to end, got $state'),
  };
  session.orchestrator.dispose();

  final replay = ExecutionBands.replayed();
  final history = await storedHistoryFromJson(observer: replay, [
    for (final (index, (runId, events)) in [
      ('run-waits', waits),
      ('run-continues', continues),
    ].indexed)
      (
        runId: runId,
        runInput: session.sent[index].toJson(),
        events: [for (final event in events) event.toJson()],
      ),
  ]);
  return (
    live: (
      messages: conversation.messages,
      messageStates: conversation.messageStates,
      bands: session.trackers.trackers,
      outcomes: conversation.runOutcomes,
    ),
    reloaded: (
      messages: history.messages,
      messageStates: history.messageStates,
      bands: replay.finish(),
      outcomes: history.runOutcomes,
    ),
  );
}

void main() {
  setUpAll(registerLiveSessionFallbacks);

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

  test('attribution survives events arriving without a pause between them',
      () async {
    // The parity cases yield after every event, so none of them exercises a
    // burst — which is what an SSE stream actually delivers.
    final sequence = [
      RunStartedEvent(threadId: 't', runId: _runId),
      ..._reasoning('r1', 'start with the manual'),
      ..._says('m1', 'Let me check the manual.'),
      ..._call('c1'),
      ..._reasoning('r2', 'enough to answer'),
      ..._says('m2', 'Off below 2,000 ft AGL.'),
      RunFinishedEvent(threadId: 't', runId: _runId),
    ];

    final paced = await _live(sequence);
    final burst = await _live(sequence, burst: true);

    expect(
      burst.bands.keys.toSet(),
      equals(paced.bands.keys.toSet()),
      reason: 'a burst must not change which message owns which band',
    );
    expect(describeBands(burst.bands), describeBands(paced.bands));
    expect(
      burst.bands['m1']!.thinkingBlocks.value,
      equals(['start with the manual']),
    );
    expect(
      burst.bands['m2']!.thinkingBlocks.value,
      equals(['enough to answer']),
    );
  });

  test('a run whose last response works but never speaks', () async {
    // `[decl] N`. The closing response emits reasoning and a tool call and no
    // message at all, so nothing speaks for it and nothing follows to take it.
    await _expectParity([
      RunStartedEvent(threadId: 't', runId: _runId),
      ..._reasoning('r1', 'let me check'),
      ..._says('m1', 'Checking the manual.'),
      ..._call('c1'),
      ..._reasoning('r2', 'one more lookup'),
      const ToolCallStartEvent(toolCallId: 'c2', toolCallName: 'fetch'),
      const ToolCallEndEvent(toolCallId: 'c2'),
      const ToolCallResultEvent(
        messageId: 'tr-c2',
        toolCallId: 'c2',
        content: 'ok',
      ),
      RunFinishedEvent(threadId: 't', runId: _runId),
    ]);
  });

  test('one response that emits two replies', () async {
    // `[decl] O`. Two messages speak with no tool result between them, so they
    // are one response and only one of them can carry its band.
    await _expectParity([
      RunStartedEvent(threadId: 't', runId: _runId),
      ..._reasoning('r1', 'two parts'),
      ..._says('m1', 'First part.'),
      ..._says('m2', 'Second part.'),
      ..._call('c1'),
      ..._reasoning('r2', 'enough to answer'),
      ..._says('m3', 'Off below 2,000 ft AGL.'),
      RunFinishedEvent(threadId: 't', runId: _runId),
    ]);
  });

  test('a reply that makes two calls at once keeps them in one response',
      () async {
    // Both results belong to the response that made the calls. Closing on the
    // first would strand the second in a band with no step for it, and leave
    // that band resolving to a tile the first one already took.
    await _expectParity([
      RunStartedEvent(threadId: 't', runId: _runId),
      ..._reasoning('r1', 'two lookups at once'),
      ..._says('m1', 'Checking both.'),
      const ToolCallStartEvent(toolCallId: 'c1', toolCallName: 'search'),
      const ToolCallEndEvent(toolCallId: 'c1'),
      const ToolCallStartEvent(toolCallId: 'c2', toolCallName: 'fetch'),
      const ToolCallEndEvent(toolCallId: 'c2'),
      const ToolCallResultEvent(
        messageId: 'tr-c1',
        toolCallId: 'c1',
        content: 'ok',
      ),
      const ToolCallResultEvent(
        messageId: 'tr-c2',
        toolCallId: 'c2',
        content: 'ok',
      ),
      ..._reasoning('r2', 'enough to answer'),
      ..._says('m2', 'Off below 2,000 ft AGL.'),
      RunFinishedEvent(threadId: 't', runId: _runId),
    ]);
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

  // A response ends because the next one begins, and the next one begins with
  // output: reasoning, text or a tool call. What can sit between a tool result
  // and that — state the tool wrote, the run ending — belongs to the response
  // that made the call. In the stored threads, 13 of 132 runs end on a result.

  test('a reply that works, then the run finishes on the result', () async {
    await _expectParity([
      RunStartedEvent(threadId: 't', runId: _runId),
      ..._says('m1', 'Let me look that up.'),
      ..._call('c1'),
      RunFinishedEvent(threadId: 't', runId: _runId),
    ]);
  });

  test('state written after a result, then the run finishes', () async {
    await _expectParity([
      RunStartedEvent(threadId: 't', runId: _runId),
      ..._says('m1', 'Let me look that up.'),
      ..._call('c1'),
      const StateSnapshotEvent(snapshot: {'k': 1}),
      RunFinishedEvent(threadId: 't', runId: _runId),
    ]);
  });

  test('state written between two parallel results', () async {
    await _expectParity([
      RunStartedEvent(threadId: 't', runId: _runId),
      ..._says('m1', 'Checking both.'),
      const ToolCallStartEvent(toolCallId: 'c1', toolCallName: 'search'),
      const ToolCallEndEvent(toolCallId: 'c1'),
      const ToolCallStartEvent(toolCallId: 'c2', toolCallName: 'fetch'),
      const ToolCallEndEvent(toolCallId: 'c2'),
      const ToolCallResultEvent(
        messageId: 'tr-c1',
        toolCallId: 'c1',
        content: 'ok',
      ),
      const StateDeltaEvent(delta: [
        {'op': 'add', 'path': '/k', 'value': 1},
      ]),
      const ToolCallResultEvent(
        messageId: 'tr-c2',
        toolCallId: 'c2',
        content: 'ok',
      ),
      ..._says('m2', 'Done.'),
      RunFinishedEvent(threadId: 't', runId: _runId),
    ]);
  });

  test('a run that fails while one of two parallel calls is still out',
      () async {
    final sequence = [
      RunStartedEvent(threadId: 't', runId: _runId),
      ..._says('m1', 'Checking both.'),
      const ToolCallStartEvent(toolCallId: 'c1', toolCallName: 'search'),
      const ToolCallEndEvent(toolCallId: 'c1'),
      const ToolCallStartEvent(toolCallId: 'c2', toolCallName: 'fetch'),
      const ToolCallEndEvent(toolCallId: 'c2'),
      const ToolCallResultEvent(
        messageId: 'tr-c1',
        toolCallId: 'c1',
        content: 'ok',
      ),
      const RunErrorEvent(message: 'upstream said no'),
    ];
    await _expectParity(sequence);

    // Parity passes when both paths paint the call that never returned green,
    // so pin how it settles.
    for (final (path, inputs) in [
      ('live', await _live(sequence)),
      ('reloaded', await _reloaded(sequence)),
    ]) {
      final c2 = inputs.bands['m1']!.timeline.value
          .whereType<TimelineStep>()
          .singleWhere((s) => s.toolCallId == 'c2');
      expect(
        c2.step.status,
        equals(StepStatus.failed),
        reason: '$path: a call the failed run never answered',
      );
    }
  });

  test('a tool reports progress between two parallel results', () async {
    await _expectParity([
      RunStartedEvent(threadId: 't', runId: _runId),
      ..._says('m1', 'Checking both.'),
      const ToolCallStartEvent(toolCallId: 'c1', toolCallName: 'search'),
      const ToolCallEndEvent(toolCallId: 'c1'),
      const ToolCallStartEvent(toolCallId: 'c2', toolCallName: 'fetch'),
      const ToolCallEndEvent(toolCallId: 'c2'),
      const ToolCallResultEvent(
        messageId: 'tr-c1',
        toolCallId: 'c1',
        content: 'ok',
      ),
      const ActivitySnapshotEvent(
        messageId: 'a1',
        activityType: 'progress',
        content: {'fetched': 1},
      ),
      const ToolCallResultEvent(
        messageId: 'tr-c2',
        toolCallId: 'c2',
        content: 'ok',
      ),
      ..._says('m2', 'Done.'),
      RunFinishedEvent(threadId: 't', runId: _runId),
    ]);
  });

  group('as the backend streams them', () {
    // The faux room's scripted scenarios, event for event as pydantic-ai's
    // AG-UI adapter emits them: a tool's state rides after its result as
    // metadata, a tool's progress arrives while it runs, and an error closes
    // any call still out with a result of its own before `RUN_ERROR`.

    List<BaseEvent> speaksThenCalls(List<String> toolCallIds) => [
          RunStartedEvent(threadId: 't', runId: _runId),
          ..._reasoning('r1', 'The manual will have this.'),
          ..._says('m1', 'Let me look that up.'),
          for (final id in toolCallIds) ...[
            ToolCallStartEvent(
              toolCallId: id,
              toolCallName: 'faux_tool',
              parentMessageId: 'm1',
            ),
            ToolCallArgsEvent(toolCallId: id, delta: '{"query":"$id"}'),
            ToolCallEndEvent(toolCallId: id),
          ],
        ];

    ToolCallResultEvent result(String id, String content) =>
        ToolCallResultEvent(
            messageId: 'tr-$id', toolCallId: id, content: content);

    const stateWritten = StateDeltaEvent(delta: [
      {'op': 'add', 'path': '/faux', 'value': 'scenario'},
    ]);

    List<BaseEvent> answers() => [
          ..._reasoning('r2', 'Enough to answer.'),
          ..._says('m2', 'Both sources agree: off below 2,000 ft AGL.'),
          RunFinishedEvent(threadId: 't', runId: _runId),
        ];

    test('the model request after a tool fails', () async {
      await _expectParity([
        ...speaksThenCalls(['c1']),
        result('c1', 'something random'),
        stateWritten,
        const RunErrorEvent(message: 'the next model request failed'),
      ]);
    });

    test('one of two calls at once raises', () async {
      final sequence = [
        ...speaksThenCalls(['c1', 'c2']),
        result('c1', 'something random'),
        stateWritten,
        result('c2', 'Tool execution was interrupted by an error.'),
        const ReasoningEncryptedValueEvent(
          subtype: ReasoningEncryptedValueSubtype.message,
          entityId: 'tr-c2',
          encryptedValue: '{"pydantic_ai": {"outcome": "failed"}}',
        ),
        const RunErrorEvent(message: 'the second lookup timed out'),
      ];
      await _expectParity(sequence);

      // Parity passes when both paths lose the closing result the same way.
      for (final (path, inputs) in [
        ('live', await _live(sequence)),
        ('reloaded', await _reloaded(sequence)),
      ]) {
        final c2 = inputs.bands['m1']!.timeline.value
            .whereType<TimelineStep>()
            .singleWhere((s) => s.toolCallId == 'c2');
        expect(
          c2.result,
          equals('Tool execution was interrupted by an error.'),
          reason: '$path: the call the error closed keeps its result',
        );
      }
    });

    test('two calls at once, each writing state, then an answer', () async {
      await _expectParity([
        ...speaksThenCalls(['c1', 'c2']),
        result('c1', 'something random'),
        stateWritten,
        result('c2', 'something random'),
        stateWritten,
        ...answers(),
      ]);
    });

    test('two calls at once, the slower reporting progress', () async {
      final sequence = [
        ...speaksThenCalls(['c1', 'c2']),
        result('c1', 'something random'),
        stateWritten,
        const ActivitySnapshotEvent(
          messageId: 'faux:c2',
          activityType: 'skill_tool_call',
          content: {'skill': 'faux', 'tool_name': 'search'},
        ),
        result('c2', 'something random'),
        stateWritten,
        ...answers(),
      ];
      await _expectParity(sequence);

      // Parity does not compare where an activity sits, so pin that it stays
      // under the reply whose call reported it.
      for (final (path, inputs) in [
        ('live', await _live(sequence)),
        ('reloaded', await _reloaded(sequence)),
      ]) {
        final answerEntries = inputs.bands['m2']!.timeline.value;
        expect(
          answerEntries.whereType<TimelineStandaloneActivity>(),
          isEmpty,
          reason: "$path: the progress landed in the answer's band",
        );
      }
    });

    test('the response after a tool thinks, then the stream breaks off',
        () async {
      final sequence = [
        ...speaksThenCalls(['c1']),
        result('c1', 'something random'),
        stateWritten,
        ..._reasoning('r2', 'One more thing to check.'),
        const RunErrorEvent(message: 'the model stream broke off'),
      ];
      await _expectParity(sequence);

      // Parity passes when both paths hand the later thinking to the reply,
      // so pin that it rides the failed run's outcome tile instead.
      for (final (path, inputs) in [
        ('live', await _live(sequence)),
        ('reloaded', await _reloaded(sequence)),
      ]) {
        final reply = inputs.bands['m1']!;
        expect(
          reply.thinkingBlocks.value,
          equals(['The manual will have this.']),
          reason: '$path: the reply carries only its own response',
        );
        expect(
          reply.timeline.value
              .whereType<TimelineStep>()
              .singleWhere((s) => s.toolCallId == 'c1')
              .result,
          equals('something random'),
          reason: '$path: the reply keeps its call',
        );
        final trailing = inputs.bands[noResponseMessageId(_runId)]!;
        expect(
          trailing.thinkingBlocks.value,
          equals(['One more thing to check.']),
          reason: '$path: the response that never spoke keeps its thinking',
        );
        final host = layOutTimeline(
          messages: inputs.messages,
          bands: inputs.bands,
          outcomes: inputs.outcomes,
          streaming: null,
          activeRunId: null,
        ).tiles.singleWhere((t) => identical(t.band, trailing)).message;
        expect(
          host,
          isA<NoResponseTile>().having(
            (t) => t.reason,
            'reason',
            TerminalReason.failed,
          ),
          reason: "$path: the later thinking rides the failed run's tile",
        );
      }
    });
  });

  test('a reply the run fails partway through', () async {
    // No TEXT_MESSAGE_END is stored, but the terminal is: both paths commit
    // the partial text, so the reply is shown and its band has to reach it.
    await _expectParity([
      RunStartedEvent(threadId: 't', runId: _runId),
      ..._reasoning('r1', 'weighing it'),
      const TextMessageStartEvent(messageId: 'm1'),
      const TextMessageContentEvent(messageId: 'm1', delta: 'Partial answ'),
      const RunErrorEvent(message: 'upstream said no'),
    ]);
  });

  group('a turn that waits on a client tool', () {
    // Live keeps one band open across the wait, so the run that ends the turn
    // takes the work of the run that waited; reload has to carry it the same
    // way, and show the tool the same way.
    test('whose run spoke before the call keeps the call with what it said',
        () async {
      // The call belongs to the response that spoke before it, and the wait
      // does not move it: it stays with what that response said, and the
      // reply that resumes the turn does not take it.
      final (:live, :reloaded) = await _clientToolTurn(
        _says('p1', 'Let me find you'),
        [
          RunStartedEvent(threadId: 't', runId: 'run-continues'),
          ..._says('m2', 'You are in Paris'),
          const RunFinishedEvent(threadId: 't', runId: 'run-continues'),
        ],
      );

      _expectSameInputs(live, reloaded);
    });

    test('keeps its work on the run that continues it, when that never speaks',
        () async {
      final (:live, :reloaded) = await _clientToolTurn(
        _reasoning('r1', 'need a location'),
        [
          RunStartedEvent(threadId: 't', runId: 'run-continues'),
          ..._reasoning('r2', 'still looking'),
          const RunFinishedEvent(threadId: 't', runId: 'run-continues'),
        ],
      );

      _expectSameInputs(live, reloaded);
      expect(reloaded.bands.keys, [noResponseMessageId('run-continues')]);
      expect(
        _thinkingOf(reloaded.bands[noResponseMessageId('run-continues')]!),
        ['need a location', 'still looking'],
      );
    });

    test('keeps the call its run finished on as done when the turn then fails',
        () async {
      // The waiting run's RUN_FINISHED reaches the band, live, before the run
      // that continues it fails. The continuation fails before it starts a
      // step of its own, so nothing else settles the call's step: without
      // that RUN_FINISHED it would still be open when the turn fails, and
      // settle as failed.
      final (:live, :reloaded) = await _clientToolTurn(
        _reasoning('r1', 'need a location'),
        [
          RunStartedEvent(threadId: 't', runId: 'run-continues'),
          const RunErrorEvent(message: 'upstream said no'),
        ],
      );

      _expectSameInputs(live, reloaded);
      final call = reloaded
          .bands[noResponseMessageId('run-continues')]!.timeline.value
          .whereType<TimelineStep>()
          .singleWhere((s) => s.toolCallId == 'c1');
      expect(call.step.status, StepStatus.completed);
    });
  });

  test('a reply a later one cuts off takes no band, though it spoke', () async {
    // msg-2 opens while msg-1 is still streaming, so only msg-2 is shown;
    // msg-1's text and end arrive for a stream no longer open. A band keyed to
    // msg-1 would name a tile that is never shown.
    final sequence = [
      RunStartedEvent(threadId: 't', runId: _runId),
      ..._reasoning('r1', 'thinking...'),
      const TextMessageStartEvent(messageId: 'msg-1'),
      const TextMessageStartEvent(messageId: 'msg-2'),
      const TextMessageContentEvent(messageId: 'msg-1', delta: 'Hi'),
      const TextMessageEndEvent(messageId: 'msg-1'),
      const TextMessageContentEvent(messageId: 'msg-2', delta: 'Yo'),
      const TextMessageEndEvent(messageId: 'msg-2'),
      RunFinishedEvent(threadId: 't', runId: _runId),
    ];
    await _expectParity(sequence);

    // Parity passes when both paths key the band to msg-1.
    final reloaded = await _reloaded(sequence);
    expect(reloaded.bands.keys, ['msg-2']);
    expect(reloaded.bands['msg-2']!.thinkingBlocks.value, ['thinking...']);
  });

  test('a reply interrupted mid-stream keeps its work after a reload',
      () async {
    // Stored with no terminal event at all: the stream stopped mid-reply.
    // Both paths commit the partial text when the events end, so the reply
    // is shown and its band has to reach it.
    await _expectParity([
      RunStartedEvent(threadId: 't', runId: _runId),
      ..._reasoning('r1', 'weighing it'),
      const TextMessageStartEvent(messageId: 'm1'),
      const TextMessageContentEvent(messageId: 'm1', delta: 'Partial answ'),
    ]);
  });
}
