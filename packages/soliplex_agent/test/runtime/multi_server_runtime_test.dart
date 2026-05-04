import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
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
// Fixtures
// ---------------------------------------------------------------------------

const _roomId = 'room-1';
const _runId = 'run-abc';

/// Creates a [ServerConnection] with fresh mocks.
({ServerConnection connection, MockSoliplexApi api, MockAgUiStreamClient agUi})
    _serverFixture(String serverId) {
  final api = MockSoliplexApi();
  final agUi = MockAgUiStreamClient();
  return (
    connection: ServerConnection(
      serverId: serverId,
      api: api,
      agUiStreamClient: agUi,
    ),
    api: api,
    agUi: agUi,
  );
}

ThreadInfo _threadInfo(String threadId) =>
    ThreadInfo(id: threadId, roomId: _roomId, createdAt: DateTime(2026));

RunInfo _runInfo(String threadId) =>
    RunInfo(id: _runId, threadId: threadId, createdAt: DateTime(2026));

List<BaseEvent> _happyPathEvents(String threadId) => [
      RunStartedEvent(threadId: threadId, runId: _runId),
      const TextMessageStartEvent(messageId: 'msg-1'),
      const TextMessageContentEvent(messageId: 'msg-1', delta: 'Hello'),
      const TextMessageEndEvent(messageId: 'msg-1'),
      RunFinishedEvent(threadId: threadId, runId: _runId),
    ];

/// Stubs a mock API + AgUiStreamClient to support a single happy-path spawn.
void _stubHappyPath(
  MockSoliplexApi api,
  MockAgUiStreamClient agUi, {
  required String threadId,
  Stream<BaseEvent>? stream,
}) {
  when(
    () => api.createThread(any()),
  ).thenAnswer((_) async => (_threadInfo(threadId), <String, dynamic>{}));
  when(
    () => api.createRun(any(), any()),
  ).thenAnswer((_) async => _runInfo(threadId));
  when(() => api.deleteThread(any(), any())).thenAnswer((_) async {});
  when(
    () => agUi.runAgent(
      any(),
      any(),
      cancelToken: any(named: 'cancelToken'),
      resumePolicy: any(named: 'resumePolicy'),
      onReconnectStatus: any(named: 'onReconnectStatus'),
    ),
  ).thenAnswer(
    (_) => stream ?? Stream.fromIterable(_happyPathEvents(threadId)),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeSimpleRunAgentInput());
    registerFallbackValue(_FakeCancelToken());
  });

  late MockLogger logger;
  late ServerRegistry registry;
  late MultiServerRuntime msr;

  // Per-server fixtures.
  late ({
    ServerConnection connection,
    MockSoliplexApi api,
    MockAgUiStreamClient agUi,
  }) prod;
  late ({
    ServerConnection connection,
    MockSoliplexApi api,
    MockAgUiStreamClient agUi,
  }) staging;

  setUp(() {
    logger = MockLogger();
    registry = ServerRegistry();
    prod = _serverFixture('prod');
    staging = _serverFixture('staging');
    registry
      ..add(prod.connection)
      ..add(staging.connection);
    msr = MultiServerRuntime(
      registry: registry,
      toolRegistryResolver: (_) async => const ToolRegistry(),
      platform: const NativePlatformConstraints(),
      logger: logger,
    );
  });

  tearDown(() async {
    await msr.dispose();
  });

  // -------------------------------------------------------------------------
  // Construction & lazy creation
  // -------------------------------------------------------------------------

  group('construction & lazy creation', () {
    test('runtimeFor creates lazily', () {
      final r1 = msr.runtimeFor('prod');
      final r2 = msr.runtimeFor('prod');

      expect(r1, same(r2));
    });

    test('runtimeFor unknown server throws StateError', () {
      expect(() => msr.runtimeFor('unknown'), throwsStateError);
    });

    test('runtimeFor after dispose throws StateError', () async {
      await msr.dispose();

      expect(() => msr.runtimeFor('prod'), throwsStateError);
    });
  });

  // -------------------------------------------------------------------------
  // Routing
  // -------------------------------------------------------------------------

  group('routing', () {
    test('spawn routes to correct server', () async {
      _stubHappyPath(prod.api, prod.agUi, threadId: 'prod-t1');

      final session = await msr.spawn(
        serverId: 'prod',
        roomId: _roomId,
        prompt: 'Hello',
      );

      expect(session.threadKey.serverId, equals('prod'));
      await session.result;
    });

    test('spawn on two servers', () async {
      _stubHappyPath(prod.api, prod.agUi, threadId: 'prod-t1');
      _stubHappyPath(staging.api, staging.agUi, threadId: 'staging-t1');

      final s1 = await msr.spawn(
        serverId: 'prod',
        roomId: _roomId,
        prompt: 'A',
      );
      final s2 = await msr.spawn(
        serverId: 'staging',
        roomId: _roomId,
        prompt: 'B',
      );

      expect(s1.threadKey.serverId, equals('prod'));
      expect(s2.threadKey.serverId, equals('staging'));

      await Future.wait([s1.result, s2.result]);
    });

    test('getSession routes by serverId', () async {
      _stubHappyPath(prod.api, prod.agUi, threadId: 'prod-t1');
      final controller = StreamController<BaseEvent>();
      _stubHappyPath(
        prod.api,
        prod.agUi,
        threadId: 'prod-t1',
        stream: controller.stream,
      );

      final session = await msr.spawn(
        serverId: 'prod',
        roomId: _roomId,
        prompt: 'Hello',
      );

      final found = msr.getSession(session.threadKey);
      expect(found, same(session));

      // Clean up
      _happyPathEvents('prod-t1').forEach(controller.add);
      await controller.close();
      await session.result;
    });

    test('getSession returns null for wrong server', () async {
      _stubHappyPath(prod.api, prod.agUi, threadId: 'prod-t1');
      final controller = StreamController<BaseEvent>();
      _stubHappyPath(
        prod.api,
        prod.agUi,
        threadId: 'prod-t1',
        stream: controller.stream,
      );

      final session = await msr.spawn(
        serverId: 'prod',
        roomId: _roomId,
        prompt: 'Hello',
      );

      // Look on staging — should not find it.
      final wrongKey = (
        serverId: 'staging',
        roomId: session.threadKey.roomId,
        threadId: session.threadKey.threadId,
      );
      expect(msr.getSession(wrongKey), isNull);

      _happyPathEvents('prod-t1').forEach(controller.add);
      await controller.close();
      await session.result;
    });

    test('getSession with valid serverId but unknown threadId', () async {
      // Touch prod so a runtime exists.
      _stubHappyPath(prod.api, prod.agUi, threadId: 'prod-t1');
      final controller = StreamController<BaseEvent>();
      _stubHappyPath(
        prod.api,
        prod.agUi,
        threadId: 'prod-t1',
        stream: controller.stream,
      );

      await msr.spawn(serverId: 'prod', roomId: _roomId, prompt: 'Hello');

      const unknownKey = (
        serverId: 'prod',
        roomId: _roomId,
        threadId: 'no-such-thread',
      );
      expect(msr.getSession(unknownKey), isNull);

      _happyPathEvents('prod-t1').forEach(controller.add);
      await controller.close();
    });
  });

  // -------------------------------------------------------------------------
  // Aggregation
  // -------------------------------------------------------------------------

  group('aggregation', () {
    test('activeSessions lifecycle', () async {
      expect(msr.activeSessions, isEmpty);

      _stubHappyPath(prod.api, prod.agUi, threadId: 'prod-t1');
      _stubHappyPath(staging.api, staging.agUi, threadId: 'staging-t1');

      final prodCtl = StreamController<BaseEvent>();
      final stagingCtl = StreamController<BaseEvent>();
      _stubHappyPath(
        prod.api,
        prod.agUi,
        threadId: 'prod-t1',
        stream: prodCtl.stream,
      );
      _stubHappyPath(
        staging.api,
        staging.agUi,
        threadId: 'staging-t1',
        stream: stagingCtl.stream,
      );

      await msr.spawn(
        serverId: 'prod',
        roomId: _roomId,
        prompt: 'A',
        autoDispose: true,
      );
      await msr.spawn(
        serverId: 'staging',
        roomId: _roomId,
        prompt: 'B',
        autoDispose: true,
      );

      expect(msr.activeSessions, hasLength(2));

      // Complete both.
      _happyPathEvents('prod-t1').forEach(prodCtl.add);
      _happyPathEvents('staging-t1').forEach(stagingCtl.add);
      await prodCtl.close();
      await stagingCtl.close();

      // Give time for completion handlers.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(msr.activeSessions, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Cross-server wait
  // -------------------------------------------------------------------------

  group('cross-server wait', () {
    test('waitAll collects results from multiple servers', () async {
      _stubHappyPath(prod.api, prod.agUi, threadId: 'prod-t1');
      _stubHappyPath(staging.api, staging.agUi, threadId: 'staging-t1');

      final s1 = await msr.spawn(
        serverId: 'prod',
        roomId: _roomId,
        prompt: 'A',
      );
      final s2 = await msr.spawn(
        serverId: 'staging',
        roomId: _roomId,
        prompt: 'B',
      );

      final results = await msr.waitAll([s1, s2]);

      expect(results, hasLength(2));
      expect(results.every((r) => r is AgentSuccess), isTrue);
    });

    test('waitAny returns first result regardless of server', () async {
      _stubHappyPath(prod.api, prod.agUi, threadId: 'prod-t1');
      _stubHappyPath(staging.api, staging.agUi, threadId: 'staging-t1');

      final s1 = await msr.spawn(
        serverId: 'prod',
        roomId: _roomId,
        prompt: 'A',
      );
      final s2 = await msr.spawn(
        serverId: 'staging',
        roomId: _roomId,
        prompt: 'B',
      );

      final result = await msr.waitAny([s1, s2]);

      expect(result, isA<AgentSuccess>());

      // Collect remaining to avoid dangling futures.
      await msr.waitAll([s1, s2]);
    });

    test('waitAll with empty list', () async {
      final results = await msr.waitAll([]);
      expect(results, isEmpty);
    });

    test('waitAny with empty list', () async {
      // Dart Future.any on empty iterable never completes; verify it
      // does not throw synchronously.
      final future = msr.waitAny([]);
      expect(future, isA<Future<AgentResult>>());

      // Cancel the dangling future by disposing.
      await msr.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  group('lifecycle', () {
    test('cancelAll cancels all servers', () async {
      final prodCtl = StreamController<BaseEvent>.broadcast();
      final stagingCtl = StreamController<BaseEvent>.broadcast();
      _stubHappyPath(
        prod.api,
        prod.agUi,
        threadId: 'prod-t1',
        stream: prodCtl.stream,
      );
      _stubHappyPath(
        staging.api,
        staging.agUi,
        threadId: 'staging-t1',
        stream: stagingCtl.stream,
      );

      final s1 = await msr.spawn(
        serverId: 'prod',
        roomId: _roomId,
        prompt: 'A',
      );
      final s2 = await msr.spawn(
        serverId: 'staging',
        roomId: _roomId,
        prompt: 'B',
      );

      // Let runs start.
      prodCtl.add(const RunStartedEvent(threadId: 'prod-t1', runId: _runId));
      stagingCtl.add(
        const RunStartedEvent(threadId: 'staging-t1', runId: _runId),
      );
      await Future<void>.delayed(Duration.zero);

      await msr.cancelAll();

      final r1 = await s1.result;
      final r2 = await s2.result;

      expect(r1, isA<AgentFailure>());
      expect(r2, isA<AgentFailure>());

      await prodCtl.close();
      await stagingCtl.close();
    });

    test('dispose cleans up all runtimes', () async {
      _stubHappyPath(prod.api, prod.agUi, threadId: 'prod-t1');

      await msr.spawn(serverId: 'prod', roomId: _roomId, prompt: 'A');

      await msr.dispose();

      expect(() => msr.runtimeFor('prod'), throwsStateError);
    });

    test('dispose is idempotent', () async {
      await msr.dispose();
      // Second dispose should be a no-op.
      await msr.dispose();
    });

    test('concurrent dispose is safe', () async {
      _stubHappyPath(prod.api, prod.agUi, threadId: 'prod-t1');

      await msr.spawn(serverId: 'prod', roomId: _roomId, prompt: 'A');

      // Two concurrent disposes should not throw.
      await Future.wait([msr.dispose(), msr.dispose()]);
    });
  });
}
