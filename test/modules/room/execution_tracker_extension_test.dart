import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/execution_tracker_extension.dart';

import '../../helpers/live_session.dart';
import '../../helpers/test_logger.dart';

const _threadId = 'thread-1';
const _key = (serverId: 'server-1', roomId: 'room-1', threadId: _threadId);
const _runId = 'run-1';

/// A session that hands its run fold to whoever observes it, step by step,
/// as the test folds it.
class _FakeSession implements AgentSession {
  final List<RunFoldObserver> _observers = [];
  RunFold? _fold;

  @override
  void Function() observeRunFold(RunFoldObserver observer) {
    _observers.add(observer);
    return () => _observers.remove(observer);
  }

  void startRun(String runId) {
    final fold = _fold = RunFold.start(
      Conversation.empty(threadId: _threadId),
      runId: runId,
      userMessageId: null,
      turnCitations: const TurnCitations.empty(),
      runCreated: null,
    );
    for (final observer in [..._observers]) {
      observer.runStarted(fold, continuesTurn: false);
    }
  }

  void fold(BaseEvent event) {
    final applied = _fold!.apply(DecodedEvent(event, const {}));
    _fold = applied.fold;
    for (final observer in [..._observers]) {
      observer.eventFolded(applied.fold, processed: applied.processed);
    }
  }

  void endRun(RunEnding ending) {
    for (final observer in [..._observers]) {
      observer.runEnded(ending);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_FakeSession.${invocation.memberName}');
}

/// How [band]'s steps stand, and whether it is frozen.
String _settled(ExecutionTracker band) => [
      for (final step in band.steps.value) step.status.name,
      if (band.isFrozen) 'frozen' else 'open',
    ].join(', ');

void main() {
  group("fed the session's run fold", () {
    late _FakeSession session;
    late ExecutionTrackerExtension ext;

    setUp(() async {
      session = _FakeSession();
      ext = ExecutionTrackerExtension(logger: testLogger());
      await ext.onAttach(session);
    });

    tearDown(() => ext.onDispose());

    /// Starts a run with a tool call still out, and returns its band.
    ExecutionTracker runWithCallOut() {
      session
        ..startRun(_runId)
        ..fold(RunStartedEvent(threadId: _threadId, runId: _runId))
        ..fold(
            const ToolCallStartEvent(toolCallId: 'c1', toolCallName: 'search'));
      return ext.trackers[noResponseMessageId(_runId)]!;
    }

    test('a run that never speaks keeps its band under its own run', () {
      // The key is the run's from the moment the band exists, so the tile that
      // stands for a run with nothing else to show for it finds its work
      // already there. Nothing is renamed on the way to an ending.
      session.startRun(_runId);
      expect(ext.trackers.containsKey(noResponseMessageId(_runId)), isTrue);

      session.endRun(RunEnding.cancelled);

      expect(ext.trackers.containsKey(noResponseMessageId(_runId)), isTrue);
    });

    group('the ending call settles the band', () {
      test('a stopped run as failed: the call did not finish', () {
        final band = runWithCallOut();

        session.endRun(RunEnding.cancelled);

        expect(_settled(band), 'failed, frozen');
      });

      test('a failed run as failed', () {
        final band = runWithCallOut();

        session.endRun(RunEnding.failed);

        expect(_settled(band), 'failed, frozen');
      });

      test('a completed run as completed', () {
        final band = runWithCallOut();

        session
          ..fold(RunFinishedEvent(threadId: _threadId, runId: _runId))
          ..endRun(RunEnding.completed);

        expect(_settled(band), 'completed, frozen');
      });

      test(
          'a run waiting on a client tool leaves it open, its RUN_FINISHED '
          'reaching it', () {
        final band = runWithCallOut();

        session
          ..fold(RunFinishedEvent(threadId: _threadId, runId: _runId))
          ..endRun(RunEnding.waitingOnClientTool);

        expect(_settled(band), 'completed, open');
      });
    });

    test('a step of the fold after dispose reaches no band', () {
      final band = runWithCallOut();
      ext.onDispose();

      session.endRun(RunEnding.cancelled);

      expect(_settled(band), 'active, open');
    });
  });

  group('a live session settles its band as it ends with no event', () {
    setUpAll(registerLiveSessionFallbacks);

    /// A live session with a tool call out, and the band holding it.
    Future<(LiveSession, ExecutionTracker)> callOut() async {
      final live = startLiveSession(key: _key, runId: _runId);
      addTearDown(live.session.dispose);
      await Future<void>.delayed(Duration.zero);
      live.events
        ..add(RunStartedEvent(threadId: _threadId, runId: _runId).toJson())
        ..add(
          const ToolCallStartEvent(toolCallId: 'c1', toolCallName: 'search')
              .toJson(),
        );
      await Future<void>.delayed(Duration.zero);
      return (live, live.trackers.trackers[noResponseMessageId(_runId)]!);
    }

    test('stopped', () async {
      final (live, band) = await callOut();

      live.session.cancel();
      await live.session.result;

      expect(_settled(band), 'failed, frozen');
    });

    test('its stream broken', () async {
      final (live, band) = await callOut();

      live.events.addError(const NetworkException(message: 'reset'));
      await live.session.result;

      expect(_settled(band), 'failed, frozen');
    });

    test('its stream ended early', () async {
      final (live, band) = await callOut();

      await live.events.close();
      await live.session.result;

      expect(_settled(band), 'failed, frozen');
    });

    test('disposed: the band is left as it was, the session gone', () async {
      final (live, band) = await callOut();

      live.session.dispose();
      await live.session.result;

      expect(_settled(band), 'active, open');
    });
  });
}
