import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/send_error.dart';
import 'package:soliplex_frontend/src/modules/room/session_spawner.dart';

class _StubAgentSession implements AgentSession {
  bool cancelCalled = false;
  bool disposed = false;

  @override
  void cancel() => cancelCalled = true;

  @override
  void dispose() => disposed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('SessionSpawner', () {
    test('emits spawning on entry and nothing else on success', () async {
      final session = _StubAgentSession();
      final transitions = <AgentSessionState?>[];
      final errorSignal = Signal<SendError?>(null);
      AgentSession? received;

      await SessionSpawner().spawn(
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

      await SessionSpawner().spawn(
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

      await SessionSpawner().spawn(
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

      await SessionSpawner().spawn(
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
        'and disposes the orphaned session', () async {
      final spawner = SessionSpawner();
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
      final spawner = SessionSpawner();
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
      final spawner = SessionSpawner();
      expect(spawner.cancel(), isFalse);
    });

    test('emits null and surfaces error when spawnFn throws synchronously',
        () async {
      final transitions = <AgentSessionState?>[];
      final errorSignal = Signal<SendError?>(null);

      await SessionSpawner().spawn(
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
      final spawner = SessionSpawner();
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
  });
}
