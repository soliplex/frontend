import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_agent/src/tools/tool_registry_resolver.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show AgUiStreamClient, SoliplexApi;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockSoliplexApi extends Mock implements SoliplexApi {}

class MockAgUiStreamClient extends Mock implements AgUiStreamClient {}

class MockLogger extends Mock implements Logger {}

class _FakeSimpleRunAgentInput extends Fake implements SimpleRunAgentInput {}

class _FakeCancelToken extends Fake implements CancelToken {}

// ---------------------------------------------------------------------------
// Test delegate
// ---------------------------------------------------------------------------

class TestDelegate implements AgentUiDelegate {
  final List<({String toolName, Map<String, dynamic> arguments})> calls = [];
  Completer<bool>? pendingCompleter;

  bool autoApprove = true;

  @override
  Future<bool> requestToolApproval({
    required AgentSession session,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String rationale,
  }) {
    calls.add((toolName: toolName, arguments: arguments));
    if (autoApprove) return Future.value(true);
    pendingCompleter = Completer<bool>();
    return pendingCompleter!.future;
  }
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _roomA = 'test-room';
const _threadId = 'test-thread';
const _runId = 'run-1';

RunInfo _runInfo([String id = _runId]) =>
    RunInfo(id: id, threadId: _threadId, createdAt: DateTime(2026));

ThreadInfo _threadInfo([String id = _threadId]) =>
    ThreadInfo(id: id, roomId: _roomA, createdAt: DateTime(2026));

List<BaseEvent> _happyPathEvents() => [
      const RunStartedEvent(threadId: _threadId, runId: _runId),
      const TextMessageStartEvent(messageId: 'msg-1'),
      const TextMessageContentEvent(messageId: 'msg-1', delta: 'Hello'),
      const TextMessageEndEvent(messageId: 'msg-1'),
      const RunFinishedEvent(threadId: _threadId, runId: _runId),
    ];

List<BaseEvent> _toolCallEvents({String toolName = 'sensitive_tool'}) => [
      const RunStartedEvent(threadId: _threadId, runId: _runId),
      ToolCallStartEvent(toolCallId: 'tc-1', toolCallName: toolName),
      const ToolCallArgsEvent(toolCallId: 'tc-1', delta: '{"action":"read"}'),
      const ToolCallEndEvent(toolCallId: 'tc-1'),
      const RunFinishedEvent(threadId: _threadId, runId: _runId),
    ];

List<BaseEvent> _resumeTextEvents() => [
      const RunStartedEvent(threadId: _threadId, runId: _runId),
      const TextMessageStartEvent(messageId: 'msg-2'),
      const TextMessageContentEvent(messageId: 'msg-2', delta: 'Done'),
      const TextMessageEndEvent(messageId: 'msg-2'),
      const RunFinishedEvent(threadId: _threadId, runId: _runId),
    ];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

void _stubHappyPath(MockSoliplexApi api, MockAgUiStreamClient streamClient) {
  when(
    () => api.createThread(any()),
  ).thenAnswer((_) async => (_threadInfo(), <String, dynamic>{}));
  when(() => api.createRun(any(), any())).thenAnswer((_) async => _runInfo());
  when(
    () => streamClient.runAgent(
      any(),
      any(),
      cancelToken: any(named: 'cancelToken'),
    ),
  ).thenAnswer((_) => Stream.fromIterable(_happyPathEvents()));
}

/// Stubs for tool yield → resume flow: first call returns tool events,
/// subsequent calls return resume text events.
void _stubToolThenResume(
  MockSoliplexApi api,
  MockAgUiStreamClient streamClient, {
  String toolName = 'test_tool',
}) {
  _stubHappyPath(api, streamClient);

  var callCount = 0;
  when(
    () => streamClient.runAgent(
      any(),
      any(),
      cancelToken: any(named: 'cancelToken'),
    ),
  ).thenAnswer((_) {
    callCount++;
    return callCount == 1
        ? Stream.fromIterable(_toolCallEvents(toolName: toolName))
        : Stream.fromIterable(_resumeTextEvents());
  });
}

AgentRuntime _createRuntime({
  required MockSoliplexApi api,
  required MockAgUiStreamClient streamClient,
  AgentUiDelegate? uiDelegate,
  ToolRegistryResolver? toolRegistryResolver,
}) {
  return AgentRuntime(
    connection: ServerConnection(
      serverId: 'default',
      api: api,
      agUiStreamClient: streamClient,
    ),
    llmProvider: AgUiLlmProvider(api: api, agUiStreamClient: streamClient),
    toolRegistryResolver:
        toolRegistryResolver ?? (_) async => const ToolRegistry(),
    platform: const NativePlatformConstraints(),
    logger: MockLogger(),
    uiDelegate: uiDelegate,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeSimpleRunAgentInput());
    registerFallbackValue(_FakeCancelToken());
  });

  group('AgentUiDelegate', () {
    group('requestApproval', () {
      test('denies when no delegate is set', () async {
        final api = MockSoliplexApi();
        final streamClient = MockAgUiStreamClient();
        _stubToolThenResume(api, streamClient);

        var approvalResult = true;
        final registry = const ToolRegistry().register(
          ClientTool(
            definition: const Tool(
              name: 'test_tool',
              description: 'A test tool',
            ),
            executor: (tc, ctx) async {
              approvalResult = await ctx.requestApproval(
                toolCallId: tc.id,
                toolName: tc.name,
                arguments: const {'action': 'test'},
                rationale: 'Test approval',
              );
              return 'ok';
            },
          ),
        );

        final runtime = _createRuntime(
          api: api,
          streamClient: streamClient,
          // No delegate → deny by default
          toolRegistryResolver: (_) async => registry,
        );

        final session = await runtime.spawn(roomId: _roomA, prompt: 'test');
        await session.result;

        expect(approvalResult, isFalse);
        await runtime.dispose();
      });

      test('routes to delegate and returns true', () async {
        final api = MockSoliplexApi();
        final streamClient = MockAgUiStreamClient();
        _stubToolThenResume(api, streamClient);
        final delegate = TestDelegate();

        var approvalResult = false;
        final registry = const ToolRegistry().register(
          ClientTool(
            definition: const Tool(
              name: 'test_tool',
              description: 'A test tool',
            ),
            executor: (tc, ctx) async {
              approvalResult = await ctx.requestApproval(
                toolCallId: tc.id,
                toolName: tc.name,
                arguments: const {'action': 'read'},
                rationale: 'Allow clipboard read?',
              );
              return 'ok';
            },
          ),
        );

        final runtime = _createRuntime(
          api: api,
          streamClient: streamClient,
          uiDelegate: delegate,
          toolRegistryResolver: (_) async => registry,
        );

        final session = await runtime.spawn(roomId: _roomA, prompt: 'test');
        await session.result;

        expect(approvalResult, isTrue);
        expect(delegate.calls, hasLength(1));
        expect(delegate.calls.first.toolName, 'test_tool');
        expect(delegate.calls.first.arguments, {'action': 'read'});
        await runtime.dispose();
      });

      test('routes to delegate and returns false', () async {
        final api = MockSoliplexApi();
        final streamClient = MockAgUiStreamClient();
        _stubToolThenResume(api, streamClient);
        final delegate = TestDelegate()..autoApprove = false;

        var approvalResult = true;
        final registry = const ToolRegistry().register(
          ClientTool(
            definition: const Tool(
              name: 'test_tool',
              description: 'A test tool',
            ),
            executor: (tc, ctx) async {
              approvalResult = await ctx.requestApproval(
                toolCallId: tc.id,
                toolName: tc.name,
                arguments: const {'action': 'read'},
                rationale: 'Allow clipboard read?',
              );
              if (!approvalResult) return 'User denied permission';
              return 'ok';
            },
          ),
        );

        final runtime = _createRuntime(
          api: api,
          streamClient: streamClient,
          uiDelegate: delegate,
          toolRegistryResolver: (_) async => registry,
        );

        final session = await runtime.spawn(roomId: _roomA, prompt: 'test');

        // Complete the pending approval with false
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        delegate.pendingCompleter?.complete(false);

        await session.result;

        expect(approvalResult, isFalse);
        expect(delegate.calls, hasLength(1));
        await runtime.dispose();
      });

      test('emits AwaitingApproval event before awaiting delegate', () async {
        final api = MockSoliplexApi();
        final streamClient = MockAgUiStreamClient();
        _stubToolThenResume(api, streamClient);
        final delegate = TestDelegate();

        final registry = const ToolRegistry().register(
          ClientTool(
            definition: const Tool(
              name: 'test_tool',
              description: 'A test tool',
            ),
            executor: (tc, ctx) async {
              await ctx.requestApproval(
                toolCallId: 'tc-1',
                toolName: 'test_tool',
                arguments: const {},
                rationale: 'Test rationale',
              );
              return 'ok';
            },
          ),
        );

        final runtime = _createRuntime(
          api: api,
          streamClient: streamClient,
          uiDelegate: delegate,
          toolRegistryResolver: (_) async => registry,
        );

        final session = await runtime.spawn(roomId: _roomA, prompt: 'test');

        // Listen for AwaitingApproval via the signal
        final events = <ExecutionEvent?>[];
        session.lastExecutionEvent.subscribe(events.add);

        await session.result;

        final awaitingEvents = events.whereType<AwaitingApproval>().toList();
        expect(awaitingEvents, hasLength(1));
        expect(awaitingEvents.first.toolCallId, 'tc-1');
        expect(awaitingEvents.first.toolName, 'test_tool');
        expect(awaitingEvents.first.rationale, 'Test rationale');
        await runtime.dispose();
      });
    });

    group('spawnChild roomId', () {
      test('defaults to parent room when omitted', () async {
        final api = MockSoliplexApi();
        final streamClient = MockAgUiStreamClient();

        var childRoomId = '';
        var threadCreateCount = 0;
        when(() => api.createThread(any())).thenAnswer((inv) async {
          threadCreateCount++;
          final room = inv.positionalArguments.first as String;
          if (threadCreateCount > 1) childRoomId = room;
          return (
            ThreadInfo(
              id: 'thread-$threadCreateCount',
              roomId: room,
              createdAt: DateTime(2026),
            ),
            <String, dynamic>{},
          );
        });

        when(
          () => api.createRun(any(), any()),
        ).thenAnswer((_) async => _runInfo());

        var runAgentCallCount = 0;
        when(
          () => streamClient.runAgent(
            any(),
            any(),
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((_) {
          runAgentCallCount++;
          if (runAgentCallCount == 1) {
            // Parent: yield a tool call
            return Stream.fromIterable([
              const RunStartedEvent(threadId: 'thread-1', runId: _runId),
              const ToolCallStartEvent(
                toolCallId: 'tc-spawn',
                toolCallName: 'spawn_tool',
              ),
              const ToolCallArgsEvent(toolCallId: 'tc-spawn', delta: '{}'),
              const ToolCallEndEvent(toolCallId: 'tc-spawn'),
              const RunFinishedEvent(threadId: 'thread-1', runId: _runId),
            ]);
          }
          if (runAgentCallCount == 2) {
            // Child
            return Stream.fromIterable([
              const RunStartedEvent(threadId: 'thread-2', runId: _runId),
              const TextMessageStartEvent(messageId: 'msg-c'),
              const TextMessageContentEvent(
                messageId: 'msg-c',
                delta: 'child done',
              ),
              const TextMessageEndEvent(messageId: 'msg-c'),
              const RunFinishedEvent(threadId: 'thread-2', runId: _runId),
            ]);
          }
          // Parent resume
          return Stream.fromIterable(_resumeTextEvents());
        });

        when(() => api.deleteThread(any(), any())).thenAnswer((_) async {});

        final registry = const ToolRegistry().register(
          ClientTool(
            definition: const Tool(
              name: 'spawn_tool',
              description: 'Spawns child',
            ),
            executor: (tc, ctx) async {
              // Omit roomId — should inherit parent's
              final child = await ctx.spawnChild(prompt: 'child task');
              await child.result;
              return 'spawned';
            },
          ),
        );

        final runtime = _createRuntime(
          api: api,
          streamClient: streamClient,
          toolRegistryResolver: (_) async => registry,
        );

        final session = await runtime.spawn(
          roomId: 'my-room',
          prompt: 'parent',
        );
        await session.result;

        expect(childRoomId, 'my-room');
        await runtime.dispose();
      });
    });
  });

  group('AwaitingApproval', () {
    test('equality', () {
      const a = AwaitingApproval(
        toolCallId: 'tc-1',
        toolName: 'clipboard',
        rationale: 'Read clipboard',
      );
      const b = AwaitingApproval(
        toolCallId: 'tc-1',
        toolName: 'clipboard',
        rationale: 'Read clipboard',
      );
      const c = AwaitingApproval(
        toolCallId: 'tc-2',
        toolName: 'clipboard',
        rationale: 'Read clipboard',
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
