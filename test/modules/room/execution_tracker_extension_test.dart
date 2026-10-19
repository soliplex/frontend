import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/execution_tracker_extension.dart';

import '../../helpers/test_logger.dart';

const _threadId = 'thread-1';
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
  });
}
