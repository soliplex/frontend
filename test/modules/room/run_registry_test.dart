import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/agent_runtime_manager.dart';
import 'package:soliplex_frontend/src/modules/room/run_registry.dart';

import '../../helpers/fakes.dart';

ServerConnection _fakeConnection(FakeSoliplexApi api) => ServerConnection(
  serverId: 'test-server',
  api: api,
  agUiStreamClient: FakeAgUiStreamClient(),
);

const _key = (serverId: 'test-server', roomId: 'room-1', threadId: 'thread-1');

const _key2 = (serverId: 'test-server', roomId: 'room-1', threadId: 'thread-2');

void main() {
  late FakeSoliplexApi api;
  late ServerConnection connection;
  late AgentRuntimeManager runtimeManager;
  late AgentRuntime runtime;
  late RunRegistry registry;

  setUp(() {
    api = FakeSoliplexApi();
    connection = _fakeConnection(api);
    runtimeManager = AgentRuntimeManager(
      platform: TestPlatformConstraints(),
      toolRegistryResolver: (_) async => const ToolRegistry(),
      logger: testLogger(),
    );
    runtime = runtimeManager.getRuntime(connection);
    registry = RunRegistry();
  });

  tearDown(() async {
    registry.dispose();
    await runtimeManager.dispose();
  });

  Future<AgentSession> spawnSession({String threadId = 'thread-1'}) async {
    return runtime.spawn(roomId: 'room-1', prompt: 'test', threadId: threadId);
  }

  test('activeSession returns registered session', () async {
    final session = await spawnSession();
    registry.register(_key, session);

    expect(registry.activeSession(_key), same(session));
  });

  test('activeSession returns null for unknown key', () {
    expect(registry.activeSession(_key), isNull);
  });

  test('completedOutcome returns null before completion', () async {
    final session = await spawnSession();
    registry.register(_key, session);

    expect(registry.completedOutcome(_key), isNull);
  });

  test('captures FailedRun when session fails', () async {
    final session = await spawnSession();
    registry.register(_key, session);

    // FakeAgUiStreamClient throws, so the session fails.
    // Wait for the result to propagate.
    try {
      await session.result;
    } on Object catch (_) {
      // result may throw or complete with failure
    }
    // Let the microtask queue flush.
    await Future<void>.delayed(Duration.zero);

    expect(registry.activeSession(_key), isNull);
    expect(registry.completedOutcome(_key), isA<FailedRun>());
  });

  test('register cancels previous session for same key', () async {
    final session1 = await spawnSession();
    registry.register(_key, session1);

    final session2 = await spawnSession();
    registry.register(_key, session2);

    // session1 should be in a terminal state (cancelled or already failed)
    expect(
      session1.state,
      anyOf(AgentSessionState.cancelled, AgentSessionState.failed),
    );
    expect(registry.activeSession(_key), same(session2));
  });

  test('tracks multiple threads independently', () async {
    final session1 = await spawnSession(threadId: 'thread-1');
    final session2 = await spawnSession(threadId: 'thread-2');

    registry.register(_key, session1);
    registry.register(_key2, session2);

    expect(registry.activeSession(_key), same(session1));
    expect(registry.activeSession(_key2), same(session2));
  });

  test('completedOutcome persists until replaced', () async {
    final session = await spawnSession();
    registry.register(_key, session);

    try {
      await session.result;
    } on Object catch (_) {}
    await Future<void>.delayed(Duration.zero);

    final outcome = registry.completedOutcome(_key);
    expect(outcome, isA<FailedRun>());

    // Reading again returns the same outcome
    expect(registry.completedOutcome(_key), same(outcome));
  });

  test('new run replaces old outcome', () async {
    final session1 = await spawnSession();
    registry.register(_key, session1);

    try {
      await session1.result;
    } on Object catch (_) {}
    await Future<void>.delayed(Duration.zero);
    expect(registry.completedOutcome(_key), isA<FailedRun>());

    // Register a new session — replaces the old outcome
    final session2 = await spawnSession();
    registry.register(_key, session2);

    expect(registry.completedOutcome(_key), isNull);
    expect(registry.activeSession(_key), same(session2));
  });

  test('dispose cancels all active sessions', () async {
    final session1 = await spawnSession(threadId: 'thread-1');
    final session2 = await spawnSession(threadId: 'thread-2');

    registry.register(_key, session1);
    registry.register(_key2, session2);

    registry.dispose();

    expect(registry.activeSession(_key), isNull);
    expect(registry.activeSession(_key2), isNull);
  });
}
