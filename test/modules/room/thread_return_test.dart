import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/room/lay_out_timeline.dart';
import 'package:soliplex_frontend/src/modules/room/run_registry.dart';
import 'package:soliplex_frontend/src/modules/room/thread_view_state.dart';

import '../../helpers/fakes.dart';
import '../../helpers/live_session.dart';

/// Leaving a thread and coming back to it. The run the user watched is held by
/// the registry, which is what the returning view shows first; the backend has
/// since recorded more than that about every run it finished.

const _key = (serverId: 'test-server', roomId: 'room-1', threadId: 'thread-1');

List<BaseEvent> _reasoning(String id, String delta) => [
      ReasoningMessageStartEvent(messageId: id),
      ReasoningMessageContentEvent(messageId: id, delta: delta),
      ReasoningMessageEndEvent(messageId: id),
    ];

List<BaseEvent> _says(String messageId, String text) => [
      TextMessageStartEvent(messageId: messageId),
      TextMessageContentEvent(messageId: messageId, delta: text),
      TextMessageEndEvent(messageId: messageId),
    ];

List<BaseEvent> _call(String toolCallId, {String? parent}) => [
      ToolCallStartEvent(
        toolCallId: toolCallId,
        toolCallName: 'search',
        parentMessageId: parent,
      ),
      ToolCallEndEvent(toolCallId: toolCallId),
      ToolCallResultEvent(
        messageId: 'tr-$toolCallId',
        toolCallId: toolCallId,
        content: 'ok',
      ),
    ];

/// A run that speaks, looks something up, then answers: two replies, each
/// with a band of its own.
List<BaseEvent> _speaksWorksAnswers(String runId) => [
      RunStartedEvent(threadId: 'thread-1', runId: runId),
      ..._reasoning('r1', 'let me look'),
      ..._says('m1', 'Let me look that up.'),
      ..._call('c1', parent: 'm1'),
      ..._reasoning('r2', 'enough to answer'),
      ..._says('m2', 'Below 2,000 ft AGL.'),
      RunFinishedEvent(threadId: 'thread-1', runId: runId),
    ];

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeSoliplexApi api;
  late AuthSession auth;
  late RunRegistry registry;

  setUpAll(registerLiveSessionFallbacks);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = FakeSoliplexApi();
    auth = AuthSession(refreshService: FakeTokenRefreshService());
    registry = RunRegistry(servers: emptyServers());
  });

  tearDown(() => registry.dispose());

  /// Views already left, which teardown must not dispose a second time.
  final left = <ThreadViewState>{};

  /// Navigates away from [view], as the room does when another thread opens.
  void leave(ThreadViewState view) {
    view.dispose();
    left.add(view);
  }

  ThreadViewState open() {
    final view = ThreadViewState(
      connection: ServerConnection(
        serverId: 'test-server',
        api: api,
        agUiStreamClient: FakeAgUiStreamClient(),
      ),
      auth: auth,
      roomId: 'room-1',
      threadId: 'thread-1',
      registry: registry,
    );
    addTearDown(() {
      if (!left.remove(view)) view.dispose();
    });
    return view;
  }

  /// Opens the thread on [history], sends from it as the room does, and
  /// streams [events] into the run, one at a time.
  Future<(ThreadViewState, LiveSession)> sendIn(
    ThreadHistory history, {
    required String runId,
    required List<BaseEvent> events,
  }) async {
    api.nextThreadHistory = history;
    final view = open();
    await _settle();
    final live = startLiveSession(
      key: _key,
      runId: runId,
      cachedHistory: history,
    );
    registry.register(_key, live.session);
    view.attachSession(live.session);
    await _settle();
    for (final event in events) {
      live.events.add(event);
      await Future<void>.delayed(Duration.zero);
    }
    await _settle();
    return (view, live);
  }

  /// What the room would render for [view] right now.
  List<RenderedTile> tilesOf(ThreadViewState view) {
    final loaded = view.messages.value as MessagesLoaded;
    return layOutTimeline(
      messages: loaded.messages,
      bands: view.executionTrackers,
      outcomes: loaded.runOutcomes,
      streaming: view.streamingState.value,
      activeRunId: view.activeRunId.value,
    ).tiles;
  }

  RenderedTile? tileOf(ThreadViewState view, String messageId) {
    for (final tile in tilesOf(view)) {
      if (tile.message.id == messageId) return tile;
    }
    return null;
  }

  test('a finished run keeps every band after navigating back', () async {
    final events = _speaksWorksAnswers('run-1');
    final (view, live) = await sendIn(
      ThreadHistory(messages: const []),
      runId: 'run-1',
      events: events,
    );
    await live.events.close();
    await _settle();
    expect(tileOf(view, 'm1')?.band, isNotNull, reason: 'precondition');
    leave(view);

    api.nextThreadHistory = await storedHistory([
      (runId: 'run-1', userMessageId: 'u1', prompt: 'Q', events: events),
    ]);
    final back = open();
    await _settle();

    expect(
      tileOf(back, 'm1')?.band?.thinkingBlocks.value,
      equals(['let me look']),
      reason: 'the first reply lost its band on the way back',
    );
    expect(
      tileOf(back, 'm2')?.band?.thinkingBlocks.value,
      equals(['enough to answer']),
      reason: 'the answer lost its band on the way back',
    );
  });

  test('a run stopped before it spoke shows the answer the backend stored',
      () async {
    final (view, live) = await sendIn(
      ThreadHistory(messages: const []),
      runId: 'run-1',
      events: [
        RunStartedEvent(threadId: 'thread-1', runId: 'run-1'),
        const ReasoningMessageStartEvent(messageId: 'r1'),
        const ReasoningMessageContentEvent(messageId: 'r1', delta: 'let me'),
      ],
    );
    live.session.cancel();
    await _settle();
    expect(
      tilesOf(view).map((t) => t.message),
      contains(isA<NoResponseTile>()),
      reason: 'precondition: the stop shows as a stopped tile',
    );
    leave(view);

    // The backend runs a stopped run to its end and stores it.
    api.nextThreadHistory = await storedHistory([
      (
        runId: 'run-1',
        userMessageId: 'u1',
        prompt: 'Q',
        events: [
          RunStartedEvent(threadId: 'thread-1', runId: 'run-1'),
          ..._reasoning('r1', 'let me look'),
          ..._call('c1'),
          ..._says('m1', 'Below 2,000 ft AGL.'),
          RunFinishedEvent(threadId: 'thread-1', runId: 'run-1'),
        ],
      ),
    ]);
    final back = open();
    await _settle();

    final tiles = tilesOf(back);
    expect(
      tiles.map((t) => t.message).whereType<NoResponseTile>(),
      isEmpty,
      reason: 'the stopped tile outlived the answer the backend stored',
    );
    expect(tileOf(back, 'm1')?.band, isNotNull,
        reason: 'the stored answer shows with its band');
  });

  test('a run still in flight keeps its turn when history lacks it', () async {
    final earlier = await storedHistory([
      (
        runId: 'run-0',
        userMessageId: 'u0',
        prompt: 'first',
        events: [
          RunStartedEvent(threadId: 'thread-1', runId: 'run-0'),
          ..._says('m0', 'First answer.'),
          RunFinishedEvent(threadId: 'thread-1', runId: 'run-0'),
        ],
      ),
    ]);
    final (view, live) = await sendIn(
      earlier,
      runId: 'run-1',
      events: [
        RunStartedEvent(threadId: 'thread-1', runId: 'run-1'),
        ..._reasoning('r1', 'let me look'),
        const TextMessageStartEvent(messageId: 'm1'),
        const TextMessageContentEvent(messageId: 'm1', delta: 'Looking'),
      ],
    );
    leave(view);

    // The backend stores a run only once it finishes.
    api.nextThreadHistory = earlier;
    final back = open();
    await _settle();

    final shown = tilesOf(back);
    expect(
      shown.map((t) => t.message).whereType<TextMessage>().map((m) => m.text),
      equals(['first', 'First answer.', 'Q', 'Looking']),
      reason: 'the turn in flight is not in history and must stay',
    );
    expect(
      tileOf(back, 'm1')?.band?.thinkingBlocks.value,
      equals(['let me look']),
      reason: 'the live band stays on the reply streaming it',
    );

    live.events
      ..add(const TextMessageContentEvent(messageId: 'm1', delta: ' it up.'))
      ..add(const TextMessageEndEvent(messageId: 'm1'))
      ..add(RunFinishedEvent(threadId: 'thread-1', runId: 'run-1'));
    await live.events.close();
    await _settle();

    expect(
      (tileOf(back, 'm1')?.message as TextMessage?)?.text,
      equals('Looking it up.'),
      reason: 'the answer finishes streaming in place',
    );
  });

  test('a run whose stream failed before the backend stored it stays failed',
      () async {
    final (view, live) = await sendIn(
      ThreadHistory(messages: const []),
      runId: 'run-1',
      events: const [],
    );
    // The stream closes before the backend sends a thing.
    await live.events.close();
    await _settle();
    expect(
      tilesOf(view).map((t) => t.message),
      contains(isA<NoResponseTile>()),
      reason: 'precondition: the failure shows as an outcome tile',
    );
    leave(view);

    api.nextThreadHistory = ThreadHistory(messages: const []);
    final back = open();
    await _settle();

    final shown = tilesOf(back).map((t) => t.message).toList();
    expect(
      shown.whereType<NoResponseTile>().map((t) => (t.runId, t.reason)),
      equals([('run-1', TerminalReason.failed)]),
      reason: 'history knows nothing of this run, so the view keeps it',
    );
    expect(
      shown.whereType<TextMessage>().map((m) => m.text),
      equals(['Q']),
      reason: 'the message that started it stays too',
    );
  });

  test('a fetch that fails on the way back keeps the restored thread',
      () async {
    final events = _speaksWorksAnswers('run-1');
    final (view, live) = await sendIn(
      ThreadHistory(messages: const []),
      runId: 'run-1',
      events: events,
    );
    await live.events.close();
    await _settle();
    final before = tilesOf(view).map((t) => t.message.id).toList();
    leave(view);

    api
      ..nextThreadHistory = null
      ..nextThreadHistoryError = Exception('offline');
    final back = open();
    await _settle();

    expect(back.messages.value, isA<MessagesLoaded>());
    expect(
      tilesOf(back).map((t) => t.message.id),
      equals(before),
      reason: 'a failed fetch must not take away what the registry restored',
    );
  });
}
