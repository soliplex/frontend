import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
// ignore: implementation_imports
import 'package:soliplex_agent/src/orchestration/run_orchestrator.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show AgUiStreamClient, SoliplexApi;

import '../../helpers/live_session.dart';
import '../../helpers/test_logger.dart';

// A run reaches the timeline by two paths: live, as `RunOrchestrator` folds the
// stream, and on reload, as `SoliplexApi.getThreadHistory` replays what the
// backend stored. Each case here feeds the same events to both and expects the
// same messages, transcript, message states and run outcomes. Data only: how
// the room lays them out is `live_reload_parity_test.dart`.

class _MockSoliplexApi extends Mock implements SoliplexApi {}

class _MockAgUiStreamClient extends Mock implements AgUiStreamClient {}

const ThreadKey _key = (serverId: 'srv', roomId: 'r', threadId: 't');

/// [event] as the stream client delivers it: sent as JSON text, decoded by
/// [decodeMapSafely], the boundary replay crosses too.
DecodeOutcome _overTheWire(Map<String, dynamic> event) =>
    decodeMapSafely(jsonDecode(jsonEncode(event)) as Map<String, dynamic>);

/// The server time [seconds] into the first run.
int _at(int seconds) =>
    DateTime.utc(2026, 1, 7, 1, 0, seconds).millisecondsSinceEpoch;

Map<String, dynamic> _citation(String chunkId) => {
      'chunk_id': chunkId,
      'content': 'Text of $chunkId',
      'document_id': 'doc-1',
      'document_uri': 'https://example.com/doc.pdf',
    };

/// The state snapshot the backend sends just before a run's terminal event,
/// citing [cited] out of [indexed].
Map<String, dynamic> _snapshot(
  int seconds, {
  required List<String> indexed,
  required List<String> cited,
}) =>
    StateSnapshotEvent(
      snapshot: {
        'rag': {
          'citation_index': {for (final id in indexed) id: _citation(id)},
          'citations': cited,
        },
      },
      timestamp: _at(seconds),
    ).toJson();

Map<String, dynamic> _runStarted(String runId, int seconds) =>
    RunStartedEvent(threadId: 't', runId: runId, timestamp: _at(seconds))
        .toJson();

Map<String, dynamic> _runFinished(String runId, int seconds) =>
    RunFinishedEvent(threadId: 't', runId: runId, timestamp: _at(seconds))
        .toJson();

/// A complete reply [text] under [messageId], one event a second from
/// [seconds].
List<Map<String, dynamic>> _reply(
  String messageId,
  String text,
  int seconds,
) =>
    [
      TextMessageStartEvent(messageId: messageId, timestamp: _at(seconds))
          .toJson(),
      TextMessageContentEvent(
        messageId: messageId,
        delta: text,
        timestamp: _at(seconds + 1),
      ).toJson(),
      TextMessageEndEvent(messageId: messageId, timestamp: _at(seconds + 2))
          .toJson(),
    ];

/// A search the backend ran and answered within the run, so the run's
/// streamed transcript holds more than it was sent.
List<Map<String, dynamic>> _serverSearch(int seconds) => [
      TextMessageStartEvent(messageId: 'p', timestamp: _at(seconds)).toJson(),
      TextMessageEndEvent(messageId: 'p', timestamp: _at(seconds)).toJson(),
      ToolCallStartEvent(
        toolCallId: 'call-search',
        toolCallName: 'search',
        parentMessageId: 'p',
        timestamp: _at(seconds + 1),
      ).toJson(),
      ToolCallArgsEvent(
        toolCallId: 'call-search',
        delta: '{}',
        timestamp: _at(seconds + 1),
      ).toJson(),
      ToolCallEndEvent(toolCallId: 'call-search', timestamp: _at(seconds + 1))
          .toJson(),
      ToolCallResultEvent(
        messageId: 'r',
        toolCallId: 'call-search',
        content: 'evidence',
        timestamp: _at(seconds + 2),
      ).toJson(),
    ];

/// Every field of [message] but a user message's `parts`, so two messages
/// compare by value. A list of text alone travels the wire as a bare string,
/// which reload reads back as no parts, while the live echo keeps the list.
Map<String, Object?> _describeMessage(ChatMessage message) => {
      'type': message.runtimeType,
      'id': message.id,
      'user': message.user,
      'createdAt': message.createdAt,
      'runId': message.runId,
      ...switch (message) {
        TextMessage(
          :final text,
          :final thinkingText,
          :final namedByToolCall,
        ) =>
          {
            'text': text,
            'thinkingText': thinkingText,
            'namedByToolCall': namedByToolCall,
          },
        NoResponseTile(
          :final thinkingText,
          :final reason,
          :final errorDetail
        ) =>
          {
            'thinkingText': thinkingText,
            'reason': reason,
            'errorDetail': errorDetail,
          },
        ErrorMessage(:final errorText) => {'errorText': errorText},
        ToolCallMessage(:final toolCalls) => {
            'toolCalls': [
              for (final call in toolCalls)
                {
                  'id': call.id,
                  'name': call.name,
                  'arguments': call.arguments,
                  'status': call.status,
                  'result': call.result,
                },
            ],
          },
        GenUiMessage(:final widgetName, :final data) => {
            'widgetName': widgetName,
            'data': data,
          },
        LoadingMessage() => const {},
        DroppedEventMessage(:final source, :final reason, :final rawPayload) =>
          {
            'source': source,
            'reason': reason,
            'rawPayload': rawPayload,
          },
      },
    };

/// What both paths must agree on, as values the matcher compares deeply.
///
/// [ChatMessage] equality is by type and id, and [ToolCallInfo] equality by id,
/// so messages and outcomes go through [_describeMessage]. [MessageState] equality covers every field except each
/// figure's bytes, which `Figure` equality leaves out.
Map<String, Object?> _parityView({
  required List<ChatMessage> messages,
  required Transcript transcript,
  required Map<String, MessageState> messageStates,
  required Map<String, NoResponseTile> runOutcomes,
}) =>
    {
      'messages': messages.map(_describeMessage).toList(),
      'transcript': {
        'messages': transcript.messages.map((m) => m.toJson()).toList(),
        // What building the transcript carries from one event to the next:
        // calls started and not ended, and ended calls with no result yet.
        'openToolCalls': {
          // ignore: invalid_use_of_internal_member
          for (final MapEntry(:key, :value) in transcript.openToolCalls.entries)
            key: {'call': value.call.toJson(), 'parentId': value.parentId},
        },
        // ignore: invalid_use_of_internal_member
        'unansweredToolCallIds': transcript.unansweredToolCallIds,
      },
      'messageStates': messageStates,
      'runOutcomes': {
        for (final MapEntry(:key, :value) in runOutcomes.entries)
          key: _describeMessage(value),
      },
    };

/// How a live run ended: its conversation, and the input each of its runs
/// was sent.
typedef _LiveRun = ({
  RunState state,
  Conversation conversation,
  List<SimpleRunAgentInput> sent,
});

void main() {
  setUpAll(registerLiveSessionFallbacks);

  /// An orchestrator whose backend answers each run, in order, with its id in
  /// [runs] and its stream; `sent` collects the input each run was sent.
  ({RunOrchestrator orchestrator, List<SimpleRunAgentInput> sent})
      liveOrchestrator(
    Map<String, Stream<DecodeOutcome>> runs, {
    required ToolRegistry toolRegistry,
  }) {
    final api = _MockSoliplexApi();
    final streamClient = _MockAgUiStreamClient();
    final runIds = runs.keys.toList();
    final streams = runs.values.toList();
    when(() => api.createRun(any(), any())).thenAnswer(
      (_) async => RunInfo(
        id: runIds.removeAt(0),
        threadId: _key.threadId,
        createdAt: DateTime.utc(2026),
      ),
    );
    final sent = <SimpleRunAgentInput>[];
    when(
      () => streamClient.runAgent(
        any(),
        any(),
        cancelToken: any(named: 'cancelToken'),
        resumePolicy: any(named: 'resumePolicy'),
        onReconnectStatus: any(named: 'onReconnectStatus'),
      ),
    ).thenAnswer((invocation) {
      sent.add(invocation.positionalArguments[1] as SimpleRunAgentInput);
      return streams.removeAt(0);
    });
    final orchestrator = RunOrchestrator(
      llmProvider: AgUiLlmProvider(api: api, agUiStreamClient: streamClient),
      toolRegistry: toolRegistry,
      logger: testLogger('orchestrator'),
    );
    addTearDown(orchestrator.dispose);
    return (orchestrator: orchestrator, sent: sent);
  }

  /// Runs [runs] live, one backend run per entry, each answered by its events
  /// over the wire.
  ///
  /// [executeTools] answers a run that waits on a client tool in
  /// [toolRegistry].
  Future<_LiveRun> runLive(
    Map<String, List<Map<String, dynamic>>> runs, {
    ToolRegistry toolRegistry = const ToolRegistry(),
    ToolExecutorCallback? executeTools,
  }) async {
    final (:orchestrator, :sent) = liveOrchestrator(
      {
        for (final MapEntry(key: runId, value: events) in runs.entries)
          runId: Stream.fromIterable(events.map(_overTheWire)),
      },
      toolRegistry: toolRegistry,
    );

    final state = await orchestrator.runToCompletion(
      key: _key,
      userMessage: [const TextPart('Q')],
      toolExecutor: executeTools ??
          (pending) => fail('no client tool expected, got $pending'),
    );
    final conversation = switch (state) {
      CompletedState(:final conversation) ||
      FailedState(:final conversation?) ||
      CancelledState(:final conversation?) =>
        conversation,
      _ => fail('expected a run that ended, got $state'),
    };
    return (state: state, conversation: conversation, sent: sent);
  }

  /// Runs [runs] live, then reloads them as the backend stored them — each
  /// run's input as live sent it, and its events — and expects both paths to
  /// arrive at the same thread.
  ///
  /// Storing the input live sent is what gives both paths one user message
  /// id: the backend stores the id the client minted.
  Future<_LiveRun> expectParity(
    Map<String, List<Map<String, dynamic>>> runs, {
    ToolRegistry toolRegistry = const ToolRegistry(),
    ToolExecutorCallback? executeTools,
  }) async {
    final live = await runLive(
      runs,
      toolRegistry: toolRegistry,
      executeTools: executeTools,
    );
    final reload = await storedHistoryFromJson([
      for (final (index, MapEntry(key: runId, value: events))
          in runs.entries.indexed)
        (
          runId: runId,
          runInput: live.sent[index].toJson(),
          events: events,
        ),
    ]);

    expect(
      _parityView(
        messages: reload.messages,
        transcript: reload.transcript,
        messageStates: reload.messageStates,
        runOutcomes: reload.runOutcomes,
      ),
      _parityView(
        messages: live.conversation.messages,
        transcript: live.conversation.transcript,
        messageStates: live.conversation.messageStates,
        runOutcomes: live.conversation.runOutcomes,
      ),
    );
    return live;
  }

  group('live and reload agree on', () {
    test('a completed run', () async {
      final live = await expectParity({
        'run-1': [
          _runStarted('run-1', 0),
          ..._reply('msg-1', 'Hello', 1),
          _runFinished('run-1', 4),
        ],
      });

      expect(live.state, isA<CompletedState>());
    });

    test('a run whose state snapshot precedes its finish', () async {
      final live = await expectParity({
        'run-1': [
          _runStarted('run-1', 0),
          ..._serverSearch(1),
          ..._reply('msg-1', 'Answer', 4),
          _snapshot(7, indexed: ['chunk-1'], cited: ['chunk-1']),
          _runFinished('run-1', 8),
        ],
      });

      expect(live.state, isA<CompletedState>());
      expect(
        live.conversation.messageStates.values.single.sourceReferences,
        hasLength(1),
      );
    });

    test('a run cut off mid-reply', () async {
      final live = await expectParity({
        'run-1': [
          _runStarted('run-1', 0),
          TextMessageStartEvent(messageId: 'msg-1', timestamp: _at(1)).toJson(),
          TextMessageContentEvent(
            messageId: 'msg-1',
            delta: "I don'",
            timestamp: _at(2),
          ).toJson(),
        ],
      });

      expect(live.state, isA<FailedState>());
    });

    test(
      'a run cut off after a state snapshot it could not process',
      skip: 'Live says "Stream ended without terminal event" where reload '
          'says "Some of this run\'s events could not be read", and leaves '
          'the drop tile undated where reload dates it at the last event; '
          'closed by PR 5 (RunOrchestrator on RunFold).',
      () async {
        final live = await expectParity({
          'run-1': [
            _runStarted('run-1', 0),
            ..._serverSearch(1),
            ..._reply('msg-1', 'Answer', 4),
            StateSnapshotEvent(
              snapshot: const ['not', 'an', 'object'],
              timestamp: _at(7),
            ).toJson(),
          ],
        });

        expect(live.state, isA<FailedState>());
        expect(
          live.conversation.messages.whereType<DroppedEventMessage>().single,
          isA<DroppedEventMessage>().having(
            (m) => m.source,
            'source',
            DropSource.eventProcessing,
          ),
        );
      },
    );

    test(
      'a run ended by a RUN_ERROR that carries no time',
      skip: 'Live leaves the failure undated where reload dates it at the '
          'last event; closed by PR 5.',
      () async {
        final live = await expectParity({
          'run-1': [
            _runStarted('run-1', 0),
            ..._reply('msg-1', 'Partial answer', 1),
            const RunErrorEvent(message: 'Injected failure').toJson(),
          ],
        });

        expect(live.state, isA<FailedState>());
      },
    );

    test('a run ended by a RUN_ERROR whose message is empty', () async {
      final live = await expectParity({
        'run-1': [
          _runStarted('run-1', 0),
          ..._reply('msg-1', 'Partial answer', 1),
          {'type': 'RUN_ERROR', 'message': '', 'timestamp': _at(4)},
        ],
      });

      expect(
        live.state,
        isA<FailedState>()
            .having((s) => s.reason, 'reason', FailureReason.serverError),
      );
      expect(live.conversation.messages,
          isNot(contains(isA<DroppedEventMessage>())));
    });

    test(
      'a run with an event that could not be decoded',
      skip: 'Live leaves the drop tile undated where reload dates it at the '
          'last event; closed by PR 5.',
      () async {
        final live = await expectParity({
          'run-1': [
            _runStarted('run-1', 0),
            {'type': 'NOT_AN_AGUI_EVENT', 'timestamp': _at(1)},
            ..._reply('msg-1', 'Hello', 2),
            _runFinished('run-1', 5),
          ],
        });

        expect(live.state, isA<CompletedState>());
        expect(
          live.conversation.messages.whereType<DroppedEventMessage>().single,
          isA<DroppedEventMessage>()
              .having((m) => m.source, 'source', DropSource.decode),
        );
      },
    );

    test(
      'a run that waits on a client tool and the run that continues it',
      skip: 'Reload keeps the outcome RUN_FINISHED parked for the run that '
          'waited on the tool, which live withdraws, and live adds a message '
          'for the executed tool, dated by the client clock, that reload '
          'lacks; closed by PR 5.',
      () async {
        final live = await expectParity(
          {
            'run-1': [
              _runStarted('run-1', 0),
              ToolCallStartEvent(
                toolCallId: 'call-locate',
                toolCallName: 'locate',
                timestamp: _at(1),
              ).toJson(),
              ToolCallArgsEvent(
                toolCallId: 'call-locate',
                delta: '{}',
                timestamp: _at(1),
              ).toJson(),
              ToolCallEndEvent(toolCallId: 'call-locate', timestamp: _at(1))
                  .toJson(),
              _snapshot(2, indexed: ['chunk-1'], cited: ['chunk-1']),
              _runFinished('run-1', 3),
            ],
            'run-2': [
              _runStarted('run-2', 60),
              ..._reply('msg-2', 'You are here', 61),
              _snapshot(
                64,
                indexed: ['chunk-1', 'chunk-2'],
                cited: ['chunk-2'],
              ),
              _runFinished('run-2', 65),
            ],
          },
          toolRegistry: const ToolRegistry().register(
            ClientTool(
              definition: const Tool(name: 'locate', description: 'Locates'),
              executor: (_, __) async => fail('answered by executeTools'),
            ),
          ),
          executeTools: (pending) async => [
            for (final call in pending)
              call.copyWith(
                status: ToolCallStatus.completed,
                result: 'Paris',
              ),
          ],
        );

        expect(live.state, isA<CompletedState>());
        expect(
          live.conversation.messageStates.values.single.sourceReferences
              .map((s) => s.chunkId),
          ['chunk-1', 'chunk-2'],
        );
      },
    );
  });

  // Not a parity case: the backend runs every run to completion after the
  // client goes (`drive_llm_stream`), so a reload shows the finished answer,
  // never a disposed run.
  test(
    'disposing mid-run keeps the partial reply and what the run was sent',
    skip: 'Dispose parks the cancel straight from parkCancelledOutcome, '
        'skipping the partial-reply commit and the sent-transcript restore '
        'that stopping a run in flight does (_recordRunEndedAsCancelled); '
        'closed by PR 5.',
    () async {
      final events = StreamController<DecodeOutcome>();
      addTearDown(events.close);
      final (:orchestrator, :sent) = liveOrchestrator(
        {'run-1': events.stream},
        toolRegistry: const ToolRegistry(),
      );
      final ended = orchestrator.runToCompletion(
        key: _key,
        userMessage: [const TextPart('Q')],
        toolExecutor: (pending) => fail('no client tool expected'),
      );
      await Future<void>.delayed(Duration.zero);
      [
        _runStarted('run-1', 0),
        ..._serverSearch(1),
        TextMessageStartEvent(messageId: 'msg-1', timestamp: _at(4)).toJson(),
        TextMessageContentEvent(
          messageId: 'msg-1',
          delta: "I don'",
          timestamp: _at(5),
        ).toJson(),
      ].map(_overTheWire).forEach(events.add);
      await Future<void>.delayed(Duration.zero);

      orchestrator.dispose();
      final state = await ended;

      final conversation = switch (state) {
        CancelledState(:final conversation?) => conversation,
        _ => fail('expected a cancelled run, got $state'),
      };
      expect(
        conversation.messages.whereType<TextMessage>().map((m) => m.text),
        contains("I don'"),
      );
      expect(
        conversation.transcript.messages.map((m) => m.toJson()),
        sent.single.messages!.map((m) => m.toJson()),
      );
    },
  );
}
