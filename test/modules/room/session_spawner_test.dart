import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:signals_core/signals_core.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/send_error.dart';
import 'package:soliplex_frontend/src/modules/room/session_spawner.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

class _FakeSession implements AgentSession {
  bool cancelCalled = false;
  bool disposeCalled = false;

  @override
  void cancel() => cancelCalled = true;

  @override
  void dispose() => disposeCalled = true;

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

void main() {
  group('SessionSpawner', () {
    late SessionSpawner spawner;
    late Signal<SendError?> errorSignal;

    setUp(() {
      spawner = SessionSpawner();
      errorSignal = Signal(null);
    });

    tearDown(() {
      spawner.dispose();
      errorSignal.dispose();
    });

    test('initial sessionState is null', () {
      expect(spawner.sessionState.value, isNull);
    });

    test('spawn sets state to spawning immediately', () async {
      final completer = Completer<AgentSession>();

      unawaited(
        spawner.spawn(
          spawnFn: () => completer.future,
          errorSignal: errorSignal,
          prompt: 'test',
          isDisposed: () => false,
          onSpawned: (_) {},
        ),
      );

      expect(spawner.sessionState.value, AgentSessionState.spawning);
      completer.complete(_FakeSession());
      await Future<void>.delayed(Duration.zero);
    });

    test('spawn calls onSpawned with the session', () async {
      final session = _FakeSession();
      AgentSession? received;

      await spawner.spawn(
        spawnFn: () async => session,
        errorSignal: errorSignal,
        prompt: 'test',
        isDisposed: () => false,
        onSpawned: (s) => received = s,
      );

      expect(received, same(session));
    });

    test('spawn leaves sessionState as spawning after success', () async {
      // The spawner does NOT auto-reset after a successful spawn.
      // Callers update state via updateState() inside onSpawned.
      await spawner.spawn(
        spawnFn: () async => _FakeSession(),
        errorSignal: errorSignal,
        prompt: 'test',
        isDisposed: () => false,
        onSpawned: (_) {},
      );

      expect(spawner.sessionState.value, AgentSessionState.spawning);
    });

    test('onSpawned can clear sessionState via updateState', () async {
      await spawner.spawn(
        spawnFn: () async => _FakeSession(),
        errorSignal: errorSignal,
        prompt: 'test',
        isDisposed: () => false,
        onSpawned: (_) => spawner.updateState(null),
      );

      expect(spawner.sessionState.value, isNull);
    });

    test('spawn clears error signal before starting', () async {
      errorSignal.value = SendError(Exception('old'));

      await spawner.spawn(
        spawnFn: () async => _FakeSession(),
        errorSignal: errorSignal,
        prompt: 'test',
        isDisposed: () => false,
        onSpawned: (_) {},
      );

      expect(errorSignal.value, isNull);
    });

    test('concurrent spawn is a no-op when sessionState is non-null', () async {
      final firstCompleter = Completer<AgentSession>();
      var spawnCount = 0;

      unawaited(
        spawner.spawn(
          spawnFn: () {
            spawnCount++;
            return firstCompleter.future;
          },
          errorSignal: errorSignal,
          prompt: 'first',
          isDisposed: () => false,
          onSpawned: (_) {},
        ),
      );

      // Second spawn while first is pending — should be ignored.
      await spawner.spawn(
        spawnFn: () {
          spawnCount++;
          return Future.value(_FakeSession());
        },
        errorSignal: errorSignal,
        prompt: 'second',
        isDisposed: () => false,
        onSpawned: (_) {},
      );

      expect(spawnCount, 1);
      firstCompleter.complete(_FakeSession());
      await Future<void>.delayed(Duration.zero);
    });

    test('spawn on error sets errorSignal when not disposed', () async {
      final error = Exception('spawn failed');

      await spawner.spawn(
        spawnFn: () async => throw error,
        errorSignal: errorSignal,
        prompt: 'my prompt',
        isDisposed: () => false,
        onSpawned: (_) {},
      );

      expect(errorSignal.value, isNotNull);
      expect(errorSignal.value!.unsentText, 'my prompt');
    });

    test('spawn on error suppressed when isDisposed returns true', () async {
      await spawner.spawn(
        spawnFn: () async => throw Exception('boom'),
        errorSignal: errorSignal,
        prompt: 'test',
        isDisposed: () => true,
        onSpawned: (_) {},
      );

      expect(errorSignal.value, isNull);
    });

    test('spawn resets sessionState to null on error', () async {
      await spawner.spawn(
        spawnFn: () async => throw Exception('boom'),
        errorSignal: errorSignal,
        prompt: 'test',
        isDisposed: () => false,
        onSpawned: (_) {},
      );

      expect(spawner.sessionState.value, isNull);
    });

    group('cancel', () {
      test('returns false when nothing is pending', () {
        expect(spawner.cancel(), isFalse);
      });

      test('returns true when a spawn is pending', () async {
        final completer = Completer<AgentSession>();

        unawaited(
          spawner.spawn(
            spawnFn: () => completer.future,
            errorSignal: errorSignal,
            prompt: 'test',
            isDisposed: () => false,
            onSpawned: (_) {},
          ),
        );

        expect(spawner.cancel(), isTrue);
        completer.complete(_FakeSession());
        await Future<void>.delayed(Duration.zero);
      });

      test('resets sessionState to null on cancel', () async {
        final completer = Completer<AgentSession>();

        unawaited(
          spawner.spawn(
            spawnFn: () => completer.future,
            errorSignal: errorSignal,
            prompt: 'test',
            isDisposed: () => false,
            onSpawned: (_) {},
          ),
        );

        spawner.cancel();

        expect(spawner.sessionState.value, isNull);
        completer.complete(_FakeSession());
        await Future<void>.delayed(Duration.zero);
      });

      test('cancelled spawn does not call onSpawned', () async {
        final completer = Completer<AgentSession>();
        var spawnedCalled = false;

        unawaited(
          spawner.spawn(
            spawnFn: () => completer.future,
            errorSignal: errorSignal,
            prompt: 'test',
            isDisposed: () => false,
            onSpawned: (_) => spawnedCalled = true,
          ),
        );

        spawner.cancel();
        completer.complete(_FakeSession());
        await Future<void>.delayed(Duration.zero);

        expect(spawnedCalled, isFalse);
      });
    });

    group('updateState', () {
      test('directly sets sessionState', () {
        spawner.updateState(AgentSessionState.running);
        expect(spawner.sessionState.value, AgentSessionState.running);
      });

      test('can clear sessionState to null', () {
        spawner.updateState(AgentSessionState.running);
        spawner.updateState(null);
        expect(spawner.sessionState.value, isNull);
      });
    });
  });
}
