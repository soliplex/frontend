import 'dart:async';

import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:test/test.dart';

const _loggerName = 'test.guarded_run_fold_observer';

RunFold _fold(String runId) => RunFold.start(
      Conversation.empty(threadId: 'thread-1'),
      runId: runId,
      userMessageId: null,
      turnCitations: const TurnCitations.empty(),
      runCreated: null,
    );

/// An observer with a bug at every step: it writes down each call it is told,
/// then throws.
class _FailingObserver implements RunFoldObserver {
  final List<String> told = [];

  @override
  void runStarted(RunFold fold, {required bool continuesTurn}) {
    told.add('${fold.runId} starts');
    throw StateError('start bug');
  }

  @override
  void eventFolded(RunFold fold, {required BaseEvent? processed}) {
    told.add('${fold.runId} folds');
    throw StateError('event bug');
  }

  @override
  void runEnded(RunEnding ending) {
    told.add('ends ${ending.name}');
    throw StateError('ending bug');
  }
}

void main() {
  late MemorySink sink;
  late _FailingObserver failing;
  late GuardedRunFoldObserver guarded;

  setUp(() {
    sink = MemorySink();
    LogManager.instance.addSink(sink);
    addTearDown(() => LogManager.instance.removeSink(sink));
    failing = _FailingObserver();
    guarded = GuardedRunFoldObserver(
      failing,
      threadId: 'thread-1',
      logger: LogManager.instance.getLogger(_loggerName),
    );
  });

  /// Each failure logged, as `<threadId> <runId> <step>`.
  List<String> logged() => [
        for (final r in sink.records)
          if (r.loggerName == _loggerName)
            [
              r.attributes['threadId'],
              r.attributes['runId'],
              r.attributes['step'],
            ].join(' '),
      ];

  /// Runs [body] in a zone of its own and returns what reached it as uncaught.
  List<Object> uncaughtIn(void Function() body) {
    final escaped = <Object>[];
    runZonedGuarded(body, (error, _) => escaped.add(error));
    return escaped;
  }

  test(
      'tells the observer every step though each throws, and logs the first '
      'failure at each step once', () {
    final escaped = uncaughtIn(() {
      final fold = _fold('run-1');
      guarded
        ..runStarted(fold, continuesTurn: false)
        ..eventFolded(fold, processed: null)
        ..eventFolded(fold, processed: null)
        ..runEnded(RunEnding.completed);
    });

    expect(failing.told, [
      'run-1 starts',
      'run-1 folds',
      'run-1 folds',
      'ends completed',
    ]);
    expect(escaped, hasLength(3));
    expect(logged(), [
      'thread-1 run-1 runStarted',
      'thread-1 run-1 eventFolded',
      'thread-1 run-1 runEnded',
    ]);
  });

  test(
      'reports a failure at a step once for as long as it lives, turn after '
      'turn, as a replay of a whole thread does', () {
    uncaughtIn(() {
      final first = _fold('run-1');
      final next = _fold('run-2');
      guarded
        ..runStarted(first, continuesTurn: false)
        ..eventFolded(first, processed: null)
        ..runStarted(next, continuesTurn: false)
        ..eventFolded(next, processed: null);
    });

    expect(logged(), [
      'thread-1 run-1 runStarted',
      'thread-1 run-1 eventFolded',
    ]);
  });
}
