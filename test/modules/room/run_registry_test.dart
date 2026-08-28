import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'package:soliplex_frontend/src/modules/auth/admin_status.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';
import 'package:soliplex_frontend/src/modules/room/agent_runtime_manager.dart';
import 'package:soliplex_frontend/src/modules/room/run_registry.dart';
import 'package:soliplex_frontend/version.dart';

import '../../helpers/fakes.dart';

ServerConnection _fakeConnection(FakeSoliplexApi api) => ServerConnection(
      serverId: 'test-server',
      api: api,
      agUiStreamClient: FakeAgUiStreamClient(),
    );

ServerEntry _entry(String serverId) {
  final connection = ServerConnection(
    serverId: serverId,
    api: FakeSoliplexApi(),
    agUiStreamClient: FakeAgUiStreamClient(),
  );
  return ServerEntry(
    serverId: serverId,
    alias: serverId,
    serverUrl: Uri.parse('https://$serverId.example.com'),
    auth: _authInActiveSession(),
    httpClient: FakeHttpClient(),
    connection: connection,
    adminStatus: AdminStatus(api: connection.api, serverId: serverId),
  );
}

AuthSession _authInActiveSession() {
  final auth = AuthSession(refreshService: FakeTokenRefreshService());
  auth.login(
    provider: const OidcProvider(
      discoveryUrl: 'https://auth.example.com/.well-known/openid-configuration',
      clientId: 'test-client',
    ),
    tokens: AuthTokens(
      accessToken: 'access',
      refreshToken: 'refresh',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    ),
  );
  return auth;
}

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
      servers: emptyServers(),
    );
    runtime = runtimeManager.getRuntime(connection);
    registry = RunRegistry(servers: emptyServers());
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
      prompt: [TextPart('test')],
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

  test('does not read session signals after external dispose', () async {
    // ThreadViewState disposes the session on view teardown; the
    // registry's result.then callback fires afterwards on the microtask
    // queue. It must not touch session.runState (already disposed).
    final session = await spawnSession();

    final captured = <String>[];
    await runZoned(
      () async {
        registry.register(_key, session);
        session.dispose();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      },
      zoneSpecification: ZoneSpecification(
        print: (_, __, ___, line) => captured.add(line),
      ),
    );

    expect(
      captured.where((line) => line.contains('read after disposed')),
      isEmpty,
      reason: 'RunRegistry must not read session signals after disposal.',
    );
    expect(registry.activeSession(_key), isNull);
    expect(registry.completedOutcome(_key), isNotNull);
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
    final session1 = ManualAgentSession(_key);
    final session2 = ManualAgentSession(_key);

    registry.register(_key, session1);
    registry.register(_key, session2);

    // session2 stays active. Trigger session1's terminal callback —
    // it must NOT remove the key.
    session1.completeAsCancelled();
    await Future<void>.delayed(Duration.zero);

    expect(registry.activeKeys.value, contains(_key));
    expect(registry.activeSession(_key), same(session2));
  });

  test('supersession guard works for any superseded run, not only the first',
      () async {
    final session1 = ManualAgentSession(_key);
    final session2 = ManualAgentSession(_key);
    final session3 = ManualAgentSession(_key);

    registry.register(_key, session1);
    registry.register(_key, session2);
    registry.register(_key, session3);

    // Terminate the middle session: it's superseded by session3
    // and the guard must protect session3's slot.
    session2.completeAsCancelled();
    await Future<void>.delayed(Duration.zero);

    expect(registry.activeKeys.value, contains(_key));
    expect(registry.activeSession(_key), same(session3));
  });

  test('outcome is derived from AgentResult when no terminal state captured',
      () async {
    // When the session's runState never transitions through a terminal
    // state (e.g. external dispose mid-run, or the synthetic flow here),
    // the registry has no live RunState to read — the outcome is
    // derived from AgentResult alone. AgentFailure(cancelled) becomes
    // CancelledRun(null) since no conversation snapshot is available.
    final session = ManualAgentSession(_key);
    registry.register(_key, session);

    session.completeWithoutTransition();
    await Future<void>.delayed(Duration.zero);

    final outcome = registry.completedOutcome(_key);
    expect(outcome, isA<CancelledRun>());
    expect((outcome! as CancelledRun).conversation, isNull);
  });

  test('dispose is idempotent', () async {
    final session = await spawnSession();
    registry.register(_key, session);

    registry.dispose();
    registry.dispose();
    // tearDown will dispose a third time.

    expect(registry.activeSession(_key), isNull);
  });

  test('register after dispose cancels the session and asserts in debug',
      () async {
    registry.dispose();

    final session = ManualAgentSession(_key);
    expect(
      () => registry.register(_key, session),
      throwsA(isA<AssertionError>()),
    );
    expect(session.cancelCalled, isTrue);
    expect(registry.activeSession(_key), isNull);
  });

  group('auto-files feedback on failure', () {
    late FakeSoliplexApi serverApi;
    late Signal<Map<String, ServerEntry>> servers;
    late RunRegistry filing;

    late AuthSession serverAuth;

    setUp(() {
      final entry = _entry('test-server');
      serverApi = entry.connection.api as FakeSoliplexApi;
      serverAuth = entry.auth;
      servers = Signal({'test-server': entry});
      filing = RunRegistry(servers: servers);
      addTearDown(() {
        filing.dispose();
        servers.dispose();
      });
    });

    /// Fails [session] and lets the registry's `result.then` microtask run.
    Future<void> fail(
      ManualAgentSession session, {
      required FailureReason reason,
      String? runId,
      String error = 'boom',
    }) async {
      session.completeAsFailed(reason: reason, runId: runId, error: error);
      await Future<void>.delayed(Duration.zero);
    }

    // No ThreadViewState exists anywhere in this group: every case here
    // proves the trigger lives in the registry, not the UI. Moving it into
    // a widget makes the whole group fail.
    test('files one thumbs-down naming the failed run', () async {
      final session = ManualAgentSession(_key);
      filing.register(_key, session);

      await fail(session, reason: FailureReason.serverError, runId: 'run-1');

      expect(serverApi.submittedFeedback, hasLength(1));
      final filed = serverApi.submittedFeedback.single;
      expect(filed.roomId, 'room-1');
      expect(filed.threadId, 'thread-1');
      expect(filed.runId, 'run-1');
      expect(filed.feedback, FeedbackType.thumbsDown);
    });

    // Every whitelisted reason, so dropping any one of them fails here.
    final filedReasons = {
      FailureReason.serverError: '[auto] serverError — boom, v$soliplexVersion',
      FailureReason.toolExecutionFailed:
          '[auto] toolExecutionFailed — boom, v$soliplexVersion',
    };
    for (final entry in filedReasons.entries) {
      test('names ${entry.key.name} in the reason it files', () async {
        final session = ManualAgentSession(_key);
        filing.register(_key, session);

        await fail(session, reason: entry.key, runId: 'run-1');

        expect(serverApi.submittedFeedback.single.reason, entry.value);
      });
    }

    test('leads with the backend message, since that is what differs',
        () async {
      // Every auto-filed row carries the same classification in practice, so a
      // triager scanning the queue needs the server's own words first.
      final session = ManualAgentSession(_key);
      filing.register(_key, session);

      await fail(
        session,
        reason: FailureReason.serverError,
        runId: 'run-1',
        error: 'upstream model returned 503',
      );

      expect(
        serverApi.submittedFeedback.single.reason,
        '[auto] serverError — upstream model returned 503, v$soliplexVersion',
      );
    });

    test('collapses and caps a sprawling server message', () async {
      // The record is prefilled into a dialog the user edits, so an error that
      // is really a response body must not run away with the field.
      final session = ManualAgentSession(_key);
      filing.register(_key, session);

      await fail(
        session,
        reason: FailureReason.serverError,
        runId: 'run-1',
        error: 'Traceback\n\n   most recent call last${'x' * 400}',
      );

      final reason = serverApi.submittedFeedback.single.reason!;
      expect(
        reason,
        startsWith('[auto] serverError — Traceback most recent call last'),
      );
      expect(reason, contains('…'));
      expect(reason, endsWith('v$soliplexVersion'));
      expect(reason.length, lessThan(280));
    });

    test('says only the classification when the run gave no message', () async {
      final session = ManualAgentSession(_key);
      filing.register(_key, session);

      await fail(
        session,
        reason: FailureReason.serverError,
        runId: 'run-1',
        error: '   ',
      );

      expect(
        serverApi.submittedFeedback.single.reason,
        '[auto] serverError, v$soliplexVersion',
      );
    });

    test('files nothing for a failure that never started a run', () async {
      final session = ManualAgentSession(_key);
      filing.register(_key, session);

      await fail(session, reason: FailureReason.serverError);

      expect(serverApi.submittedFeedback, isEmpty);
    });

    test('files nothing when the connection dropped', () async {
      // The backend keeps a run alive after a client disconnect, so these
      // often go on to succeed: filing would record a completed run as failed.
      final lost = ManualAgentSession(_key);
      filing.register(_key, lost);
      await fail(lost, reason: FailureReason.networkLost, runId: 'run-1');

      final resumeFailed = ManualAgentSession(_key2);
      filing.register(_key2, resumeFailed);
      await fail(
        resumeFailed,
        reason: FailureReason.streamResumeFailed,
        runId: 'run-2',
      );

      expect(serverApi.submittedFeedback, isEmpty);
    });

    test('logs an unclassified failure against its run instead of filing',
        () async {
      // internalError is classifyError's fallback, so the backend may still
      // complete the run — filing would send a reviewer to a run that
      // succeeded. The log is what keeps it findable, and the orchestrator's
      // own record does not name the run.
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));

      final session = ManualAgentSession(_key);
      filing.register(_key, session);

      await fail(session, reason: FailureReason.internalError, runId: 'run-1');

      expect(serverApi.submittedFeedback, isEmpty);
      final record = sink.records.singleWhere(
        (r) => r.message == 'Run failed without filing feedback',
      );
      expect(record.attributes['runId'], 'run-1');
      expect(record.attributes['reason'], 'internalError');
    });

    test('does not log a failure it deliberately ignores', () async {
      // A dropped connection is not ours to answer for, so it gets neither a
      // record nor a log line.
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));

      final session = ManualAgentSession(_key);
      filing.register(_key, session);

      await fail(session, reason: FailureReason.networkLost, runId: 'run-1');

      expect(
        sink.records.where(
          (r) => r.message == 'Run failed without filing feedback',
        ),
        isEmpty,
      );
    });

    test('files nothing when the run was throttled', () async {
      final session = ManualAgentSession(_key);
      filing.register(_key, session);

      await fail(session, reason: FailureReason.rateLimited, runId: 'run-1');

      expect(serverApi.submittedFeedback, isEmpty);
    });

    test('files nothing when the failure was an authz verdict', () async {
      final expired = ManualAgentSession(_key);
      filing.register(_key, expired);
      await fail(expired, reason: FailureReason.authExpired, runId: 'run-1');

      final denied = ManualAgentSession(_key2);
      filing.register(_key2, denied);
      await fail(
        denied,
        reason: FailureReason.permissionDenied,
        runId: 'run-2',
      );

      expect(serverApi.submittedFeedback, isEmpty);
    });

    test('files for a run superseded after it had already failed', () async {
      // A superseded run that already failed is exactly a failure worth
      // recording, so the trigger sits above the supersession bail.
      final failed = ManualAgentSession(_key);
      filing.register(_key, failed);
      filing.register(_key, ManualAgentSession(_key));

      await fail(failed, reason: FailureReason.serverError, runId: 'run-1');

      expect(serverApi.submittedFeedback.single.runId, 'run-1');
    });

    test('files nothing once the run\'s server is gone', () async {
      final session = ManualAgentSession(_key);
      filing.register(_key, session);
      servers.value = {};

      await fail(session, reason: FailureReason.serverError, runId: 'run-1');

      expect(serverApi.submittedFeedback, isEmpty);
    });

    test('expires the session when the filing meets a dead grant', () async {
      // Matches ThreadViewState.submitFeedback: a 401 anywhere is proof the
      // grant is dead, and the user must be sent to re-auth rather than left
      // looking at a signed-in UI until their next action fails.
      serverApi.nextSubmitFeedbackError =
          const AuthException(message: 'expired', statusCode: 401);
      final session = ManualAgentSession(_key);
      filing.register(_key, session);

      await fail(session, reason: FailureReason.serverError, runId: 'run-1');

      expect(serverAuth.session.value, isA<ExpiredSession>());
    });

    test('keeps the session on a filing failure that is not a 401', () async {
      // Flipping to ExpiredSession on any throw would lock the user out for a
      // recoverable failure — see AuthSession.refreshIfExpiringSoon.
      serverApi.nextSubmitFeedbackError =
          const NetworkException(message: 'offline');
      final session = ManualAgentSession(_key);
      filing.register(_key, session);

      await fail(session, reason: FailureReason.serverError, runId: 'run-1');

      expect(serverAuth.session.value, isA<ActiveSession>());
    });
  });

  test('evicts runs whose server is removed from the signal', () async {
    final servers = Signal<Map<String, ServerEntry>>({});
    final evicting = RunRegistry(servers: servers);
    addTearDown(() {
      evicting.dispose();
      servers.dispose();
    });

    const keyS1 = (serverId: 's1', roomId: 'r', threadId: 't');
    const keyS2 = (serverId: 's2', roomId: 'r', threadId: 't');
    final s1Session = ManualAgentSession(keyS1);
    final s2Session = ManualAgentSession(keyS2);
    servers.value = {'s1': _entry('s1'), 's2': _entry('s2')};
    evicting.register(keyS1, s1Session);
    evicting.register(keyS2, s2Session);

    servers.value = {'s2': _entry('s2')};

    expect(s1Session.cancelCalled, isTrue);
    expect(evicting.activeSession(keyS1), isNull);
    expect(evicting.activeKeys.value, isNot(contains(keyS1)));
    // A surviving server's run is untouched.
    expect(evicting.activeSession(keyS2), same(s2Session));
    expect(evicting.activeKeys.value, contains(keyS2));
  });

  test('evicts the removed server\'s completed outcome, not just live runs',
      () async {
    final servers = Signal<Map<String, ServerEntry>>({});
    final evicting = RunRegistry(servers: servers);
    addTearDown(() {
      evicting.dispose();
      servers.dispose();
    });

    const key = (serverId: 's1', roomId: 'r', threadId: 't');
    const survivorKey = (serverId: 's2', roomId: 'r', threadId: 't');
    final session = ManualAgentSession(key);
    final survivor = ManualAgentSession(survivorKey);
    servers.value = {'s1': _entry('s1'), 's2': _entry('s2')};
    evicting.register(key, session);
    evicting.register(survivorKey, survivor);
    session.completeAsCancelled();
    survivor.completeAsCancelled();
    await Future<void>.delayed(Duration.zero);
    expect(evicting.completedOutcome(key), isNotNull);
    expect(evicting.completedOutcome(survivorKey), isNotNull);

    servers.value = {'s2': _entry('s2')};

    expect(evicting.completedOutcome(key), isNull);
    // A surviving server's completed outcome is retained.
    expect(evicting.completedOutcome(survivorKey), isNotNull);
  });

  test('eviction survives a session whose cancel throws', () async {
    final servers = Signal<Map<String, ServerEntry>>({});
    final evicting = RunRegistry(servers: servers);
    addTearDown(() {
      evicting.dispose();
      servers.dispose();
    });

    const throwingKey = (serverId: 's1', roomId: 'r', threadId: 't1');
    const normalKey = (serverId: 's1', roomId: 'r', threadId: 't2');
    final throwing = _ThrowingCancelSession(throwingKey);
    final normal = ManualAgentSession(normalKey);
    servers.value = {'s1': _entry('s1')};
    // Register the throwing session first so it is iterated first (insertion
    // order): that is what proves the surviving session is still evicted after
    // the throw, and catches a guard that wraps the whole loop instead of the
    // single cancel.
    evicting.register(throwingKey, throwing);
    evicting.register(normalKey, normal);

    // A throwing cancel must not abort the eviction fan-out (which runs
    // synchronously inside the servers-signal write and would otherwise unwind
    // removeServer).
    expect(() => servers.value = <String, ServerEntry>{}, returnsNormally);

    expect(evicting.activeSession(throwingKey), isNull);
    expect(evicting.activeSession(normalKey), isNull);
    expect(normal.cancelCalled, isTrue);
    expect(evicting.activeKeys.value, isEmpty);
  });
}

/// Session whose [cancel] throws, to exercise the eviction guard.
class _ThrowingCancelSession extends ManualAgentSession {
  _ThrowingCancelSession(super.threadKey);

  @override
  void cancel() => throw StateError('cancel boom');
}
