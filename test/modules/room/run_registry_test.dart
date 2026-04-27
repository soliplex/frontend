import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/agent_runtime_manager.dart';
import 'package:soliplex_frontend/src/modules/room/run_registry.dart';

import '../../helpers/fakes.dart';

/// Session fake whose result future is controlled by the test, so the
/// terminal callback can be triggered at a chosen point.
class _ManualSession implements AgentSession {
  _ManualSession(this.threadKey);

  @override
  final ThreadKey threadKey;
  final Completer<AgentResult> _resultCompleter = Completer<AgentResult>();
  final Signal<RunState> _runState = Signal<RunState>(const IdleState());
  bool cancelCalled = false;

  @override
  Future<AgentResult> get result => _resultCompleter.future;

  @override
  ReadonlySignal<RunState> get runState => _runState;

  @override
  void cancel() {
    cancelCalled = true;
  }

  void completeAsCancelled() {
    _runState.value = CancelledState(threadKey: threadKey);
    _resultCompleter.complete(AgentFailure(
      threadKey: threadKey,
      reason: FailureReason.cancelled,
      error: 'cancelled',
    ));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

ServerConnection _fakeConnection(FakeSoliplexApi api) => ServerConnection(
      serverId: 'test-server',
      api: api,
      agUiStreamClient: FakeAgUiStreamClient(),
    );

const _key = (
  serverId: 'test-server',
  roomId: 'room-1',
  threadId: 'thread-1',
);

const _key2 = (
  serverId: 'test-server',
  roomId: 'room-1',
  threadId: 'thread-2',
);

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

  Future<AgentSession> spawnSession({
    String threadId = 'thread-1',
  }) async {
    return runtime.spawn(
      roomId: 'room-1',
      prompt: 'test',
      threadId: threadId,
    );
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

  test('activeKeys adds on register and removes on terminal completion',
      () async {
    expect(registry.activeKeys.value, isEmpty);

    final session = await spawnSession();
    registry.register(_key, session);

    expect(registry.activeKeys.value, contains(_key));

    try {
      await session.result;
    } on Object catch (_) {}
    await Future<void>.delayed(Duration.zero);

    expect(registry.activeKeys.value, isNot(contains(_key)));
  });

  test('activeKeys keeps key when prior session terminates after replacement',
      () async {
    // Use manual sessions so we can control when each terminates.
    final session1 = _ManualSession(_key);
    final session2 = _ManualSession(_key);

    registry.register(_key, session1);
    registry.register(_key, session2);

    // session2 stays active. Trigger session1's terminal callback —
    // it must NOT remove the key.
    session1.completeAsCancelled();
    await Future<void>.delayed(Duration.zero);

    expect(registry.activeKeys.value, contains(_key));
    expect(registry.activeSession(_key), same(session2));
  });

  test('dispose is idempotent', () async {
    final session = await spawnSession();
    registry.register(_key, session);

    registry.dispose();
    registry.dispose();
    // tearDown will dispose a third time.

    expect(registry.activeSession(_key), isNull);
  });

  test('register after dispose cancels the session and is a no-op', () async {
    registry.dispose();

    final session = _ManualSession(_key);
    registry.register(_key, session);

    expect(registry.activeSession(_key), isNull);
    // The session must be cancelled — otherwise its underlying stream
    // stays open and is leaked.
    expect(session.cancelCalled, isTrue);
  });
}
