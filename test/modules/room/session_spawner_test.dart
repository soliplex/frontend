import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/room/send_error.dart';
import 'package:soliplex_frontend/src/modules/room/session_spawner.dart';

import '../../helpers/fakes.dart';

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

class _StubAgentSession implements AgentSession {
  bool cancelCalled = false;
  bool disposed = false;

  @override
  void cancel() => cancelCalled = true;

  @override
  void dispose() => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        '_StubAgentSession.${invocation.memberName}',
      );
}

void main() {
  group('SessionSpawner', () {
    test('emits spawning on entry and nothing else on success', () async {
      final session = _StubAgentSession();
      final transitions = <AgentSessionState?>[];
      final errorSignal = Signal<SendError?>(null);
      AgentSession? received;

      await SessionSpawner(auth: _authInActiveSession()).spawn(
        spawnFn: () async => session,
        errorSignal: errorSignal,
        prompt: 'hi',
        isDisposed: () => false,
        onSpawned: (s) => received = s,
        onStateTransition: transitions.add,
      );

      expect(transitions, [AgentSessionState.spawning]);
      expect(received, same(session));
      expect(errorSignal.value, isNull);
    });

    test('emits null and surfaces error when spawn future fails', () async {
      final transitions = <AgentSessionState?>[];
      final errorSignal = Signal<SendError?>(null);

      await SessionSpawner(auth: _authInActiveSession()).spawn(
        spawnFn: () async => throw StateError('boom'),
        errorSignal: errorSignal,
        prompt: 'hi',
        isDisposed: () => false,
        onSpawned: (_) {},
        onStateTransition: transitions.add,
      );

      expect(transitions, [AgentSessionState.spawning, isNull]);
      expect(errorSignal.value, isNotNull);
      expect(errorSignal.value!.unsentText, 'hi');
    });

    test('emits null and surfaces error when onSpawned throws', () async {
      final transitions = <AgentSessionState?>[];
      final errorSignal = Signal<SendError?>(null);

      await SessionSpawner(auth: _authInActiveSession()).spawn(
        spawnFn: () async => _StubAgentSession(),
        errorSignal: errorSignal,
        prompt: 'hi',
        isDisposed: () => false,
        onSpawned: (_) => throw StateError('attach failed'),
        onStateTransition: transitions.add,
      );

      expect(transitions, [AgentSessionState.spawning, isNull]);
      expect(errorSignal.value, isNotNull);
      expect(errorSignal.value!.unsentText, 'hi');
    });

    test(
        'disposed-during-spawn does not surface error but still '
        'emits null transition', () async {
      final transitions = <AgentSessionState?>[];
      final errorSignal = Signal<SendError?>(null);

      await SessionSpawner(auth: _authInActiveSession()).spawn(
        spawnFn: () async => throw StateError('boom'),
        errorSignal: errorSignal,
        prompt: 'hi',
        isDisposed: () => true,
        onSpawned: (_) {},
        onStateTransition: transitions.add,
      );

      expect(transitions, [AgentSessionState.spawning, isNull]);
      expect(errorSignal.value, isNull);
    });

    test(
        'cancel during spawn suppresses transition and error, '
        'and disposes the spawned session', () async {
      final spawner = SessionSpawner(auth: _authInActiveSession());
      final transitions = <AgentSessionState?>[];
      final errorSignal = Signal<SendError?>(null);
      final completer = Completer<AgentSession>();
      var onSpawnedCalled = false;

      final spawnFuture = spawner.spawn(
        spawnFn: () => completer.future,
        errorSignal: errorSignal,
        prompt: 'hi',
        isDisposed: () => false,
        onSpawned: (_) => onSpawnedCalled = true,
        onStateTransition: transitions.add,
      );
      expect(transitions, [AgentSessionState.spawning]);

      expect(spawner.cancel(), isTrue);

      final session = _StubAgentSession();
      completer.complete(session);
      await spawnFuture;
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(transitions, [AgentSessionState.spawning]);
      expect(errorSignal.value, isNull);
      expect(onSpawnedCalled, isFalse);
      expect(session.cancelCalled, isTrue);
      expect(session.disposed, isTrue);
    });

    test('re-entrant spawn is a no-op while another is in-flight', () async {
      final spawner = SessionSpawner(auth: _authInActiveSession());
      final transitions = <AgentSessionState?>[];
      final errorSignal = Signal<SendError?>(null);
      final firstCompleter = Completer<AgentSession>();
      final firstSession = _StubAgentSession();
      final secondSession = _StubAgentSession();
      AgentSession? firstReceived;
      var secondOnSpawnedCalled = false;
      var secondSpawnFnCalled = false;

      final firstSpawn = spawner.spawn(
        spawnFn: () => firstCompleter.future,
        errorSignal: errorSignal,
        prompt: 'first',
        isDisposed: () => false,
        onSpawned: (s) => firstReceived = s,
        onStateTransition: transitions.add,
      );
      expect(transitions, [AgentSessionState.spawning]);
      expect(spawner.isSpawning, isTrue);

      // Re-entrant call while first is in flight.
      await spawner.spawn(
        spawnFn: () async {
          secondSpawnFnCalled = true;
          return secondSession;
        },
        errorSignal: errorSignal,
        prompt: 'second',
        isDisposed: () => false,
        onSpawned: (_) => secondOnSpawnedCalled = true,
        onStateTransition: transitions.add,
      );

      expect(secondSpawnFnCalled, isFalse);
      expect(secondOnSpawnedCalled, isFalse);
      expect(transitions, [AgentSessionState.spawning]);

      // Let the first spawn complete cleanly.
      firstCompleter.complete(firstSession);
      await firstSpawn;
      expect(firstReceived, same(firstSession));
    });

    test('cancel returns false when nothing is pending', () {
      final spawner = SessionSpawner(auth: _authInActiveSession());
      expect(spawner.cancel(), isFalse);
    });

    test(
        'late-arriving AuthException after cancel still funnels through '
        'markSessionExpired', () async {
      // The cancelled-spawn cleanup awaits the pending future. If it
      // eventually rejects with AuthException, the auth state machine
      // is the singleton funnel and still needs the signal — otherwise
      // a 401 that arrived just after cancel is silently swallowed.
      final auth = _authInActiveSession();
      final spawner = SessionSpawner(auth: auth);
      final completer = Completer<AgentSession>();

      unawaited(spawner.spawn(
        spawnFn: () => completer.future,
        errorSignal: Signal<SendError?>(null),
        prompt: 'hi',
        isDisposed: () => false,
        onSpawned: (_) {},
        onStateTransition: (_) {},
      ));
      expect(spawner.cancel(), isTrue);

      completer.completeError(
        AuthException(statusCode: 401, message: 'JWT validation failed'),
      );
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(auth.session.value, isA<ExpiredSession>());
    });

    test('emits null and surfaces error when spawnFn throws synchronously',
        () async {
      final transitions = <AgentSessionState?>[];
      final errorSignal = Signal<SendError?>(null);

      await SessionSpawner(auth: _authInActiveSession()).spawn(
        spawnFn: () => throw StateError('sync boom'),
        errorSignal: errorSignal,
        prompt: 'hi',
        isDisposed: () => false,
        onSpawned: (_) {},
        onStateTransition: transitions.add,
      );

      expect(transitions, [AgentSessionState.spawning, isNull]);
      expect(errorSignal.value, isNotNull);
      expect(errorSignal.value!.unsentText, 'hi');
    });

    test(
        'cancel after successful spawn returns false and leaves '
        'the session untouched', () async {
      final spawner = SessionSpawner(auth: _authInActiveSession());
      final session = _StubAgentSession();

      await spawner.spawn(
        spawnFn: () async => session,
        errorSignal: Signal<SendError?>(null),
        prompt: 'hi',
        isDisposed: () => false,
        onSpawned: (_) {},
        onStateTransition: (_) {},
      );

      expect(spawner.isSpawning, isFalse);
      expect(spawner.cancel(), isFalse);
      expect(session.cancelCalled, isFalse);
      expect(session.disposed, isFalse);
    });

    test('funnels AuthException from spawnFn through markSessionExpired',
        () async {
      final auth = _authInActiveSession();
      final errorSignal = Signal<SendError?>(null);
      final spawner = SessionSpawner(auth: auth);

      String? authExpiredPrompt;
      await spawner.spawn(
        spawnFn: () => Future<AgentSession>.error(
          AuthException(statusCode: 401, message: 'JWT validation failed'),
        ),
        errorSignal: errorSignal,
        prompt: 'hello',
        isDisposed: () => false,
        onSpawned: (_) => fail('spawn should not have succeeded'),
        onStateTransition: (_) {},
        onAuthExpired: (prompt) => authExpiredPrompt = prompt,
      );

      expect(auth.session.value, isA<ExpiredSession>());
      expect(
        errorSignal.value,
        isNull,
        reason: 'AuthException is funneled; the inline banner stays clear so '
            'the route guard can redirect cleanly.',
      );
      expect(
        authExpiredPrompt,
        'hello',
        reason: 'onAuthExpired receives the prompt so the caller can persist '
            'the composer before the route guard redirects.',
      );
    });

    test('AuthException without onAuthExpired still funnels', () async {
      final auth = _authInActiveSession();
      final errorSignal = Signal<SendError?>(null);
      final spawner = SessionSpawner(auth: auth);

      await spawner.spawn(
        spawnFn: () => Future<AgentSession>.error(
          AuthException(statusCode: 401, message: 'JWT validation failed'),
        ),
        errorSignal: errorSignal,
        prompt: 'hello',
        isDisposed: () => false,
        onSpawned: (_) => fail('spawn should not have succeeded'),
        onStateTransition: (_) {},
      );

      expect(auth.session.value, isA<ExpiredSession>());
      expect(errorSignal.value, isNull);
    });

    test('surfaces PermissionDeniedException inline without funneling',
        () async {
      final auth = _authInActiveSession();
      final errorSignal = Signal<SendError?>(null);
      final spawner = SessionSpawner(auth: auth);

      await spawner.spawn(
        spawnFn: () => Future<AgentSession>.error(
          PermissionDeniedException(statusCode: 403, message: 'Forbidden'),
        ),
        errorSignal: errorSignal,
        prompt: 'hello',
        isDisposed: () => false,
        onSpawned: (_) => fail('spawn should not have succeeded'),
        onStateTransition: (_) {},
      );

      expect(auth.session.value, isA<ActiveSession>());
      expect(errorSignal.value, isNotNull);
      expect(errorSignal.value!.error, isA<PermissionDeniedException>());
      expect(errorSignal.value!.unsentText, 'hello');
    });

    test('generic error still surfaces inline (regression)', () async {
      final auth = _authInActiveSession();
      final errorSignal = Signal<SendError?>(null);
      final spawner = SessionSpawner(auth: auth);

      await spawner.spawn(
        spawnFn: () => Future<AgentSession>.error(Exception('network down')),
        errorSignal: errorSignal,
        prompt: 'hello',
        isDisposed: () => false,
        onSpawned: (_) => fail('spawn should not have succeeded'),
        onStateTransition: (_) {},
      );

      expect(auth.session.value, isA<ActiveSession>());
      expect(errorSignal.value, isNotNull);
      expect(errorSignal.value!.unsentText, 'hello');
    });
  });
}
