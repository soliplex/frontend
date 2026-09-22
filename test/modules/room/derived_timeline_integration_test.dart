import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
// ignore: implementation_imports
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_agent/src/orchestration/run_orchestrator.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show AgUiStreamClient, SoliplexApi;
import 'package:soliplex_logging/soliplex_logging.dart';

import 'package:soliplex_frontend/src/modules/room/execution_tracker_extension.dart';
import 'package:soliplex_frontend/src/modules/room/lay_out_timeline.dart';

import '../../helpers/test_logger.dart';

/// What the timeline shows for a run driven through the real event path.
///
/// Hand-built inputs establish that [layOutTimeline] behaves correctly given
/// those inputs. They cannot establish that anything *produces* them — and the
/// band keys it places by are minted three layers away, in a registry that
/// only ever sees streaming states. This drives AG-UI events through the real
/// `RunOrchestrator` → `AgentSession` → `ExecutionTrackerExtension` path and
/// lays out whatever comes back.

class _MockApi extends Mock implements SoliplexApi {}

class _MockStreamClient extends Mock implements AgUiStreamClient {}

class _MockRuntime extends Mock implements AgentRuntime {}

class _FakeInput extends Fake implements SimpleRunAgentInput {}

class _FakeCancelToken extends Fake implements CancelToken {}

const _key = (serverId: 's', roomId: 'r', threadId: 't');
const _runId = 'run-abc';
const _loggerName = 'derived_timeline_integration';

/// Captures this file's own log records so an unexpected report is a test
/// failure rather than a line nobody reads.
class _RecordingSink implements LogSink {
  final List<LogRecord> records = [];

  List<LogRecord> get warnings =>
      records.where((r) => r.level == LogLevel.warning).toList();

  @override
  void write(LogRecord record) {
    if (record.loggerName == _loggerName) records.add(record);
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeInput());
    registerFallbackValue(_FakeCancelToken());
    registerFallbackValue(const (serverId: 'f', roomId: 'f', threadId: 'f'));
  });

  late _MockApi api;
  late _MockStreamClient streamClient;
  late RunOrchestrator orchestrator;
  late AgentSession session;
  late ExecutionTrackerExtension ext;
  late StreamController<BaseEvent> events;
  late _RecordingSink sink;
  late Logger logger;

  setUp(() async {
    sink = _RecordingSink();
    LogManager.instance.addSink(sink);
    addTearDown(() => LogManager.instance.removeSink(sink));
    logger = testLogger(_loggerName);

    api = _MockApi();
    streamClient = _MockStreamClient();
    events = StreamController<BaseEvent>();
    addTearDown(() async {
      if (!events.isClosed) await events.close();
    });

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
      (_) => events.stream.map<DecodeOutcome>(
        (e) => DecodedEvent(e, const {}),
      ),
    );

    orchestrator = RunOrchestrator(
      llmProvider: AgUiLlmProvider(api: api, agUiStreamClient: streamClient),
      toolRegistry: const ToolRegistry(),
      logger: testLogger('orchestrator'),
    );
    addTearDown(orchestrator.dispose);

    ext = ExecutionTrackerExtension(logger: testLogger('ext'));
    final runtime = _MockRuntime();
    when(() => runtime.ensureThreadState(any())).thenReturn(ThreadState());
    // Built directly rather than through `AgentRuntime.spawn`: spawning would
    // need the thread-resolution and runtime plumbing stubbed too, and every
    // mock added between the events and the tiles is fidelity this test
    // exists to avoid spending.
    // ignore: invalid_use_of_internal_member
    session = AgentSession(
      threadKey: _key,
      ephemeral: false,
      depth: 0,
      runtime: runtime,
      orchestrator: orchestrator,
      toolRegistry: const ToolRegistry(),
      coordinator: SessionCoordinator([ext], logger: testLogger('coord')),
      logger: testLogger('session'),
    );
  });

  /// Lays out whatever the run has produced so far, exactly as the screen
  /// does: the conversation and streaming state the orchestrator is holding,
  /// and the bands the extension has accumulated.
  List<RenderedTile> render() {
    final state = orchestrator.currentState;
    final (conversation, streaming, activeRunId) = switch (state) {
      RunningState(:final conversation, :final streaming, :final runId) => (
          conversation,
          streaming,
          runId,
        ),
      CompletedState(:final conversation) => (conversation, null, null),
      FailedState(:final conversation) => (conversation, null, null),
      CancelledState(:final conversation) => (conversation, null, null),
      _ => (null, null, null),
    };
    if (conversation == null) return const [];
    return layOutTimeline(
      messages: conversation.messages,
      bands: ext.trackers,
      outcomes: conversation.runOutcomes,
      streaming: streaming,
      activeRunId: activeRunId,
      logger: logger,
    );
  }

  List<String> idsOf(List<RenderedTile> tiles) =>
      [for (final t in tiles) t.message.id];

  Future<void> emit(BaseEvent event) async {
    events.add(event);
    await Future<void>.delayed(Duration.zero);
  }

  /// Starts the run through the session, the way the app does — the session
  /// is what subscribes the extension to the orchestrator's states.
  Future<void> start() async {
    unawaited(session.start(userMessage: [const TextPart('Q')]));
    await Future<void>.delayed(Duration.zero);
  }

  group('a reply as it arrives', () {
    test('START before content shows the loading tile, carrying the band',
        () async {
      await start();
      await emit(RunStartedEvent(threadId: 't', runId: _runId));
      await emit(const ReasoningMessageStartEvent(messageId: 'reason-1'));
      await emit(const TextMessageStartEvent(messageId: 'm1'));

      final tiles = render();
      expect(idsOf(tiles).last, equals(loadingMessageId));
      expect(
        tiles.last.band,
        isNotNull,
        reason: 'the steps already on screen must have somewhere to render',
      );
      expect(tiles.last.runId, equals(_runId));
      expect(sink.warnings, isEmpty);
    });

    test('CONTENT shows the partial reply, still carrying the band', () async {
      await start();
      await emit(RunStartedEvent(threadId: 't', runId: _runId));
      await emit(const ReasoningMessageStartEvent(messageId: 'reason-1'));
      await emit(
        const ReasoningMessageContentEvent(
          messageId: 'reason-1',
          delta: 'weighing it',
        ),
      );
      await emit(const TextMessageStartEvent(messageId: 'm1'));
      await emit(
        const TextMessageContentEvent(messageId: 'm1', delta: 'Half an ans'),
      );

      final tiles = render();
      final reply = tiles.last;
      expect(reply.message.id, equals('m1'));
      expect((reply.message as TextMessage).text, equals('Half an ans'));
      expect(reply.band, isNotNull);
      expect(reply.runId, equals(_runId));
      expect(sink.warnings, isEmpty);
    });

    test('END leaves one committed reply and no duplicate of it', () async {
      await start();
      await emit(RunStartedEvent(threadId: 't', runId: _runId));
      await emit(const TextMessageStartEvent(messageId: 'm1'));
      await emit(
        const TextMessageContentEvent(messageId: 'm1', delta: 'Here.'),
      );
      await emit(const TextMessageEndEvent(messageId: 'm1'));
      await emit(const RunFinishedEvent(threadId: 't', runId: _runId));

      final tiles = render();
      expect(idsOf(tiles).where((id) => id == 'm1'), hasLength(1));
      expect(idsOf(tiles), isNot(contains(loadingMessageId)));
      expect(
        idsOf(tiles),
        isNot(contains(noResponseMessageId(_runId))),
        reason: 'the reply stands for the run; it is not owed a tile too',
      );
      expect(sink.warnings, isEmpty);
    });

    test('a failure after the reply committed keeps it and reports once',
        () async {
      // The other error timing. A rule that decided from the streaming state
      // alone gets this one wrong: by the time the error lands there is no
      // reply in flight, only a committed one that must survive.
      await start();
      await emit(RunStartedEvent(threadId: 't', runId: _runId));
      await emit(const TextMessageStartEvent(messageId: 'm1'));
      await emit(
        const TextMessageContentEvent(messageId: 'm1', delta: 'Here.'),
      );
      await emit(const TextMessageEndEvent(messageId: 'm1'));
      await emit(const RunErrorEvent(message: 'upstream said no'));

      final tiles = render();
      final reply = tiles.firstWhere((t) => t.message.id == 'm1');
      expect((reply.message as TextMessage).text, equals('Here.'));
      expect(
        idsOf(tiles),
        isNot(contains(noResponseMessageId(_runId))),
        reason: 'the reply stands for the run; it did answer',
      );
      expect(
        idsOf(tiles).where((id) => id.startsWith('run-error')),
        hasLength(1),
        reason: 'one failure, one row, beside the reply that survived',
      );
      expect(sink.warnings, isEmpty);
    });

    test('a failure mid-reply keeps the partial text and reports once',
        () async {
      await start();
      await emit(RunStartedEvent(threadId: 't', runId: _runId));
      await emit(const TextMessageStartEvent(messageId: 'm1'));
      await emit(
        const TextMessageContentEvent(messageId: 'm1', delta: 'Half an ans'),
      );
      await emit(const RunErrorEvent(message: 'upstream said no'));

      final tiles = render();
      final reply = tiles.firstWhere((t) => t.message.id == 'm1');
      expect((reply.message as TextMessage).text, equals('Half an ans'));
      expect(
        idsOf(tiles).where((id) => id.startsWith('run-error')),
        hasLength(1),
        reason: 'one failure, one row',
      );
      expect(sink.warnings, isEmpty);
    });
  });

  test('a response that opens with a tool call hides it and keeps its work',
      () async {
    // The case the whole change exists for, driven end to end: the producer
    // opens an empty message purely to give the tool call a parent, works,
    // then answers. The empty message must not be shown, and its work must
    // arrive on the answer rather than nowhere.
    await start();
    await emit(RunStartedEvent(threadId: 't', runId: _runId));
    await emit(const TextMessageStartEvent(messageId: 'm1'));
    await emit(const TextMessageEndEvent(messageId: 'm1'));
    await emit(
      const ToolCallStartEvent(
        toolCallId: 'c1',
        toolCallName: 'search',
        parentMessageId: 'm1',
      ),
    );
    await emit(const ToolCallEndEvent(toolCallId: 'c1'));
    await emit(
      const ToolCallResultEvent(
        toolCallId: 'c1',
        content: 'ok',
        messageId: 'tool-1',
      ),
    );
    await emit(const TextMessageStartEvent(messageId: 'm2'));
    await emit(const TextMessageContentEvent(messageId: 'm2', delta: 'Here.'));
    await emit(const TextMessageEndEvent(messageId: 'm2'));
    await emit(const RunFinishedEvent(threadId: 't', runId: _runId));

    final tiles = render();

    expect(
      idsOf(tiles),
      isNot(contains('m1')),
      reason: 'the message that only names the tool call is not shown',
    );
    final answer = tiles.firstWhere((t) => t.message.id == 'm2');
    expect(
      answer.band,
      isNotNull,
      reason: "the tool round's steps belong to the answer, not to nowhere",
    );
    expect(answer.band!.steps.value, isNotEmpty);
    expect(answer.runId, equals(_runId));
    expect(
      sink.warnings,
      isEmpty,
      reason: 'a band with no tile is a defect report, not routine',
    );
  });

  test('a run that works and never answers keeps its work on its own tile',
      () async {
    await start();
    await emit(RunStartedEvent(threadId: 't', runId: _runId));
    await emit(const TextMessageStartEvent(messageId: 'm1'));
    await emit(const TextMessageEndEvent(messageId: 'm1'));
    await emit(
      const ToolCallStartEvent(
        toolCallId: 'c1',
        toolCallName: 'search',
        parentMessageId: 'm1',
      ),
    );
    await emit(const ToolCallEndEvent(toolCallId: 'c1'));
    await emit(const RunFinishedEvent(threadId: 't', runId: _runId));

    final tiles = render();

    expect(idsOf(tiles), isNot(contains('m1')));
    final outcome = tiles.firstWhere(
      (t) => t.message.id == noResponseMessageId(_runId),
    );
    expect(
      outcome.band,
      isNotNull,
      reason: 'the run is over and its steps still have to render somewhere',
    );
    expect(outcome.band!.steps.value, isNotEmpty);
    expect(sink.warnings, isEmpty);
  });
}
