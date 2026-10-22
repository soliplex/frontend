import 'dart:async';
import 'dart:convert';

import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_agent/src/orchestration/run_orchestrator.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show AgUiStreamClient, SoliplexApi;
import 'package:test/test.dart';

// A run still going on the backend is followed rather than started: its
// stored events, then the rest, are read from its first event on. Followed or
// started, the same events must leave the same conversation.

class _MockSoliplexApi extends Mock implements SoliplexApi {}

class _MockAgUiStreamClient extends Mock implements AgUiStreamClient {}

class _MockLogger extends Mock implements Logger {}

class _FakeSimpleRunAgentInput extends Fake implements SimpleRunAgentInput {}

class _FakeCancelToken extends Fake implements CancelToken {}

const ThreadKey _key = (serverId: 'srv', roomId: 'room', threadId: 'thread');
const _runId = 'run-1';
const _endpoint = 'rooms/room/agui/thread/$_runId';

/// [event] as the stream client delivers it: sent as JSON text, decoded by
/// [decodeMapSafely].
DecodeOutcome _overTheWire(Map<String, dynamic> event) =>
    decodeMapSafely(jsonDecode(jsonEncode(event)) as Map<String, dynamic>);

int _at(int seconds) =>
    DateTime.utc(2026, 1, 7, 1, 0, seconds).millisecondsSinceEpoch;

Map<String, dynamic> _citation(String chunkId) => {
      'chunk_id': chunkId,
      'content': 'Text of $chunkId',
      'document_id': 'doc-1',
      'document_uri': 'https://example.com/doc.pdf',
    };

/// A run that streams a reply, cites a source, and finishes, with one event
/// the decoder rejects along the way.
List<Map<String, dynamic>> _answeredRun() => [
      RunStartedEvent(threadId: 'thread', runId: _runId, timestamp: _at(0))
          .toJson(),
      TextMessageStartEvent(messageId: 'm-1', timestamp: _at(1)).toJson(),
      TextMessageContentEvent(
        messageId: 'm-1',
        delta: 'Sunny',
        timestamp: _at(2),
      ).toJson(),
      {'type': 'TEXT_MESSAGE_CONTENT'},
      TextMessageEndEvent(messageId: 'm-1', timestamp: _at(3)).toJson(),
      StateSnapshotEvent(
        snapshot: {
          'rag': {
            'citation_index': {'c-1': _citation('c-1')},
            'citations': ['c-1'],
          },
        },
        timestamp: _at(4),
      ).toJson(),
      RunFinishedEvent(threadId: 'thread', runId: _runId, timestamp: _at(5))
          .toJson(),
    ];

/// The thread before the run: one earlier turn.
ThreadHistory _earlierTurn() => ThreadHistory(
      messages: [
        TextMessage.create(id: 'u-0', user: ChatUser.user, text: 'Earlier'),
        TextMessage.create(
          id: 'a-0',
          user: ChatUser.assistant,
          text: 'Before',
        ),
      ],
    );

/// The run in progress as history reports it: the message it was sent, under
/// the id the client that sent it gave it.
final _followed = RunInProgress(
  runId: _runId,
  userMessage: TextMessage.create(
    id: 'user-stored',
    user: ChatUser.user,
    text: 'Weather?',
    runId: _runId,
  ),
);

/// Everything the conversation holds that a reader sees or sends, with the
/// user message's id, which a live send mints and a followed run reads from
/// its input, written as [userId].
String _view(Conversation conversation, String userId) => jsonEncode(
      {
        'messages': [
          for (final m in conversation.messages)
            {
              'type': '${m.runtimeType}',
              'id': m.id,
              'user': '${m.user}',
              'createdAt': '${m.createdAt}',
              'runId': m.runId,
              if (m is TextMessage) 'text': m.text,
              if (m is DroppedEventMessage) 'reason': m.reason,
            },
        ],
        'transcript': [
          for (final m in conversation.transcript.messages) m.toJson(),
        ],
        'messageStates': {
          for (final MapEntry(:key, :value)
              in conversation.messageStates.entries)
            key: {
              'userMessageId': value.userMessageId,
              'runId': value.runId,
              'sources': [
                for (final s in value.sourceReferences) s.chunkId,
              ],
            },
        },
        'runOutcomes': {
          for (final MapEntry(:key, :value) in conversation.runOutcomes.entries)
            key: '${value.reason} ${value.errorDetail} ${value.createdAt}',
        },
      },
    ).replaceAll(userId, 'USER');

Conversation _conversationOf(RunState state) => switch (state) {
      CompletedState(:final conversation) => conversation,
      FailedState(:final conversation?) => conversation,
      CancelledState(:final conversation?) => conversation,
      _ => throw StateError('no conversation in $state'),
    };

Future<List<ToolCallInfo>> _noTools(List<ToolCallInfo> pending) async =>
    pending;

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeSimpleRunAgentInput());
    registerFallbackValue(_FakeCancelToken());
  });

  late _MockSoliplexApi api;
  late _MockAgUiStreamClient client;
  late RunOrchestrator orchestrator;

  setUp(() {
    api = _MockSoliplexApi();
    client = _MockAgUiStreamClient();
    orchestrator = _orchestrator(api, client, const ToolRegistry());
  });

  tearDown(() => orchestrator.dispose());

  void stubFollow(Stream<DecodeOutcome> events) {
    when(
      () => client.followRun(
        _endpoint,
        _runId,
        cancelToken: any(named: 'cancelToken'),
        onReconnectStatus: any(named: 'onReconnectStatus'),
      ),
    ).thenAnswer((_) => events);
  }

  test(
      'a followed run ends in the conversation a live run of the same events '
      'ends in', () async {
    when(() => api.createRun('room', 'thread')).thenAnswer(
      (_) async => RunInfo(
        id: _runId,
        threadId: 'thread',
        createdAt: DateTime.utc(2026),
      ),
    );
    when(
      () => client.runAgent(
        _endpoint,
        any(),
        cancelToken: any(named: 'cancelToken'),
        resumePolicy: any(named: 'resumePolicy'),
        onReconnectStatus: any(named: 'onReconnectStatus'),
      ),
    ).thenAnswer((_) => Stream.fromIterable(_answeredRun().map(_overTheWire)));
    final live = await orchestrator.runToCompletion(
      key: _key,
      userMessage: [const TextPart('Weather?')],
      toolExecutor: _noTools,
      cachedHistory: _earlierTurn(),
    );
    final liveConversation = _conversationOf(live);
    final liveUserId = liveConversation.messages[2].id;

    final follower = _orchestrator(api, client, const ToolRegistry());
    addTearDown(follower.dispose);
    stubFollow(Stream.fromIterable(_answeredRun().map(_overTheWire)));
    final followed = await follower.followToCompletion(
      key: _key,
      run: _followed,
      toolExecutor: _noTools,
      cachedHistory: _earlierTurn(),
    );

    expect(live, isA<CompletedState>());
    expect(
      followed,
      isA<CompletedState>().having((s) => s.runId, 'runId', _runId),
    );
    expect(
      _view(_conversationOf(followed), 'user-stored'),
      _view(liveConversation, liveUserId),
    );
  });

  test('Stop while following records the run cancelled, keeping its reply',
      () async {
    final events = StreamController<DecodeOutcome>();
    addTearDown(() => unawaited(events.close()));
    stubFollow(events.stream);
    final ended = orchestrator.followToCompletion(
      key: _key,
      run: _followed,
      toolExecutor: _noTools,
      cachedHistory: null,
    );
    for (final event in _answeredRun().take(3)) {
      events.add(_overTheWire(event));
    }
    await pumpEventQueue();

    orchestrator.cancelRun();

    final state = await ended;
    expect(state, isA<CancelledState>());
    final conversation = _conversationOf(state);
    expect(
      [for (final m in conversation.messages.whereType<TextMessage>()) m.text],
      ['Weather?', 'Sunny'],
    );
    expect(
      conversation.runOutcomes[_runId]?.reason,
      TerminalReason.cancelled,
    );
  });

  test('a followed stream that ends without a terminal event is cut off',
      () async {
    stubFollow(Stream.fromIterable(_answeredRun().take(3).map(_overTheWire)));

    final state = await orchestrator.followToCompletion(
      key: _key,
      run: _followed,
      toolExecutor: _noTools,
      cachedHistory: null,
    );

    expect(
      state,
      isA<FailedState>()
          .having((s) => s.reason, 'reason', FailureReason.streamEndedEarly),
    );
  });

  test(
      'a followed run that waits on a client tool runs the tool and '
      'continues the turn in a new run, as a live one does', () async {
    final registry = const ToolRegistry().register(
      ClientTool(
        definition: const Tool(name: 'weather', description: 'Weather'),
        executor: (_, __) async => 'sunny',
      ),
    );
    const lowBandwidth = {'agui_sse_delivery': 'low_bandwidth'};
    final follower = _orchestrator(
      api,
      client,
      registry,
      forwardedProps: () => lowBandwidth,
    );
    addTearDown(follower.dispose);
    stubFollow(
      Stream.fromIterable(
        [
          RunStartedEvent(threadId: 'thread', runId: _runId).toJson(),
          const ToolCallStartEvent(toolCallId: 'tc-1', toolCallName: 'weather')
              .toJson(),
          const ToolCallArgsEvent(toolCallId: 'tc-1', delta: '{}').toJson(),
          const ToolCallEndEvent(toolCallId: 'tc-1').toJson(),
          const RunFinishedEvent(threadId: 'thread', runId: _runId).toJson(),
        ].map(_overTheWire),
      ),
    );
    Object? resumeSent;
    when(() => api.createRun('room', 'thread')).thenAnswer(
      (_) async => RunInfo(
        id: 'run-2',
        threadId: 'thread',
        createdAt: DateTime.utc(2026),
      ),
    );
    when(
      () => client.runAgent(
        'rooms/room/agui/thread/run-2',
        any(),
        cancelToken: any(named: 'cancelToken'),
        resumePolicy: any(named: 'resumePolicy'),
        onReconnectStatus: any(named: 'onReconnectStatus'),
      ),
    ).thenAnswer((invocation) {
      final input = invocation.positionalArguments[1] as SimpleRunAgentInput;
      resumeSent = input.toJson()['forwardedProps'];
      return Stream.fromIterable(
        [
          RunStartedEvent(threadId: 'thread', runId: 'run-2').toJson(),
          const RunFinishedEvent(threadId: 'thread', runId: 'run-2').toJson(),
        ].map(_overTheWire),
      );
    });

    final state = await follower.followToCompletion(
      key: _key,
      run: _followed,
      toolExecutor: (pending) async => [
        for (final call in pending)
          call.copyWith(status: ToolCallStatus.completed, result: 'sunny'),
      ],
      cachedHistory: null,
    );

    expect(
      state,
      isA<CompletedState>().having((s) => s.runId, 'runId', 'run-2'),
    );
    expect(resumeSent, lowBandwidth);
  });
}

RunOrchestrator _orchestrator(
  SoliplexApi api,
  AgUiStreamClient client,
  ToolRegistry registry, {
  ForwardedPropsResolver? forwardedProps,
}) =>
    RunOrchestrator(
      llmProvider: AgUiLlmProvider(api: api, agUiStreamClient: client),
      toolRegistry: registry,
      logger: _MockLogger(),
      forwardedProps: forwardedProps,
    );
