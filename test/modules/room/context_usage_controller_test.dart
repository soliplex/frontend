import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_frontend/src/modules/room/context_usage_controller.dart';

class MockSoliplexApi extends Mock implements SoliplexApi {}

const _roomId = 'room-1';
const _threadId = 'thread-1';
const _noDebounce = Duration.zero;

RunUsage _usage(String runId, {int? finalInputTokens}) => RunUsage(
      runId: runId,
      inputTokens: 9999,
      outputTokens: 1,
      requests: 1,
      toolCalls: 0,
      finalInputTokens: finalInputTokens,
    );

ThreadHistory _history(RunUsage? latest) =>
    ThreadHistory(messages: const [], latestUsage: latest);

void main() {
  late MockSoliplexApi api;

  ContextUsageController build({int? window = 8192, Duration? debounce}) =>
      ContextUsageController(
        api: api,
        roomId: _roomId,
        threadId: _threadId,
        contextWindow: window,
        draftDebounce: debounce ?? _noDebounce,
      );

  void runAnswers(String runId, RunUsage? usage) {
    when(() => api.getRunUsage(_roomId, _threadId, runId))
        .thenAnswer((_) async => usage);
  }

  setUp(() {
    api = MockSoliplexApi();
  });

  group('before anything is known', () {
    test('reads as nothing measured', () {
      final usage = build().usage;

      expect(usage.tokens, isNull);
      expect(usage.fractionUsed, isNull);
    });

    test('a draft alone yields no percentage, even against a known window',
        () async {
      // Nothing has counted the instructions, tool schemas or chat
      // template, so the draft is not a fraction of the window — showing
      // it as one reads catastrophically low on a full thread.
      final controller = build(window: 8192)
        ..draftChanged('something being typed');
      await Future<void>.delayed(Duration.zero);

      expect(controller.usage.estimatedTokens, greaterThan(0));
      expect(controller.usage.tokens, isNull);
      expect(controller.usage.fractionUsed, isNull);
    });
  });

  group('the window', () {
    test('can arrive after the controller does', () async {
      // The room loads on its own schedule.
      final controller = build(window: null)
        ..historyLoaded(_history(_usage('run-1', finalInputTokens: 1800)));
      expect(controller.usage.fractionUsed, isNull);

      controller.contextWindow = 8192;

      expect(controller.usage.fractionUsed, closeTo(1800 / 8192, 1e-9));
    });

    test('absent leaves the reading windowless', () async {
      // Ollama and an OpenAI-compatible base URL report none. A bare
      // count is shown, never a percentage against a guess.
      final controller = build(window: null)
        ..historyLoaded(_history(_usage('run-1', finalInputTokens: 1800)));

      expect(controller.usage.tokens, 1800);
      expect(controller.usage.contextWindow, isNull);
      expect(controller.usage.fractionUsed, isNull);
    });
  });

  group('the history', () {
    test('supplies the measurement, exactly', () async {
      final controller = build()
        ..historyLoaded(_history(_usage('run-1', finalInputTokens: 1800)));

      expect(controller.usage.tokens, 1800);
      expect(controller.usage.isExact, isTrue);
      expect(controller.measured?.runId, 'run-1');
    });

    test('notifies once when the reading moves', () async {
      final controller = build();
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.historyLoaded(_history(_usage('run-1', finalInputTokens: 1)));

      expect(notifications, 1);
    });

    test('does not notify for the same run again', () async {
      final controller = build()
        ..historyLoaded(_history(_usage('run-1', finalInputTokens: 1)));
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.historyLoaded(_history(_usage('run-1', finalInputTokens: 1)));

      expect(notifications, 0);
    });
  });

  group('a run ending', () {
    test('adopts the run\'s own usage', () async {
      runAnswers('run-2', _usage('run-2', finalInputTokens: 2400));
      final controller = build()
        ..historyLoaded(_history(_usage('run-1', finalInputTokens: 1800)));

      await controller.runEnded('run-2');

      expect(controller.usage.tokens, 2400);
      expect(controller.measured?.runId, 'run-2');
    });

    test('that measured nothing keeps the previous reading', () async {
      // It never reached the model, so the previous run's request is
      // still the last one the model saw.
      runAnswers('run-2', null);
      final controller = build()
        ..historyLoaded(_history(_usage('run-1', finalInputTokens: 1800)));

      await controller.runEnded('run-2');

      expect(controller.usage.tokens, 1800);
      expect(controller.measured?.runId, 'run-1');
    });

    test('recorded without a measurement is treated the same', () async {
      runAnswers('run-2', _usage('run-2'));
      final controller = build()
        ..historyLoaded(_history(_usage('run-1', finalInputTokens: 1800)));

      await controller.runEnded('run-2');

      expect(controller.measured?.runId, 'run-1');
    });

    test('keeps the last honest reading when the backend fails', () async {
      when(() => api.getRunUsage(_roomId, _threadId, 'run-2'))
          .thenThrow(const NetworkException(message: 'down'));
      final controller = build()
        ..historyLoaded(_history(_usage('run-1', finalInputTokens: 1800)));

      await controller.runEnded('run-2');

      expect(controller.usage.tokens, 1800);
    });

    test('keeps it when the fetch fails with an Error', () async {
      // The call is started with `unawaited`, so anything this throws
      // has nowhere to go. An empty run id reaches `ArgumentError`,
      // which is not an `Exception`.
      when(() => api.getRunUsage(_roomId, _threadId, 'run-2'))
          .thenThrow(ArgumentError.value('', 'runId', 'must not be empty'));
      final controller = build()
        ..historyLoaded(_history(_usage('run-1', finalInputTokens: 1800)));

      await expectLater(controller.runEnded('run-2'), completes);

      expect(controller.usage.tokens, 1800);
    });
  });

  group('the newest measurement', () {
    test('is not displaced by a slower answer about an older run', () async {
      // Two runs end in quick succession and their fetches race. The
      // reading is about the last request the model saw, so the older
      // run's answer is not news however late it arrives.
      final slowAnswer = Completer<RunUsage?>();
      when(() => api.getRunUsage(_roomId, _threadId, 'run-2'))
          .thenAnswer((_) => slowAnswer.future);
      runAnswers('run-3', _usage('run-3', finalInputTokens: 4000));
      final controller = build();

      final pending = controller.runEnded('run-2');
      await controller.runEnded('run-3');
      slowAnswer.complete(_usage('run-2', finalInputTokens: 1000));
      await pending;

      expect(controller.usage.tokens, 4000);
      expect(controller.measured?.runId, 'run-3');
    });

    test('is not displaced by a history load that resolves later', () async {
      // The history is a seed, not a correction: it was fetched before
      // this run ended, so it cannot be newer than it.
      runAnswers('run-2', _usage('run-2', finalInputTokens: 2400));
      final controller = build();
      await controller.runEnded('run-2');

      controller
          .historyLoaded(_history(_usage('run-1', finalInputTokens: 1800)));

      expect(controller.usage.tokens, 2400);
      expect(controller.measured?.runId, 'run-2');
    });

    test('is taken from the history when a fetch produced none', () async {
      // A fetch that failed measured nothing, so it displaces nothing:
      // the history's record is the only reading there is, and an
      // indicator that asked once must not go blank for good.
      when(() => api.getRunUsage(_roomId, _threadId, 'run-2'))
          .thenThrow(const NetworkException(message: 'down'));
      final controller = build();
      await controller.runEnded('run-2');

      controller
          .historyLoaded(_history(_usage('run-1', finalInputTokens: 1800)));

      expect(controller.usage.tokens, 1800);
      expect(controller.measured?.runId, 'run-1');
    });
  });

  group('a draft sent before the debounce elapses', () {
    test('is banked whole', () async {
      // Paste and hit send: both land inside the 300ms window, so the
      // stored draft is still empty when the message goes.
      final controller = build(debounce: const Duration(milliseconds: 300))
        ..historyLoaded(_history(_usage('run-1', finalInputTokens: 1000)));

      final pasted = 'a long message pasted and sent in one motion. ' * 20;
      controller
        ..draftChanged(pasted)
        ..draftSent(pasted);

      expect(controller.usage.tokens, greaterThan(1100));
    });
  });

  group('an estimate a measurement does account for', () {
    test('is released by the run its seed already named', () async {
      // The history walk is slow, so it can answer after the run it names
      // has finished -- seeding the reading with the very run whose usage
      // is still in flight. That answer covers the message sent, so the
      // estimate standing in for it still has to come out.
      final answer = Completer<RunUsage?>();
      when(() => api.getRunUsage(_roomId, _threadId, 'run-1'))
          .thenAnswer((_) => answer.future);
      final controller = build();

      controller.draftSent('a message already on its way');
      final banked = controller.usage.estimatedTokens;
      final pending = controller.runEnded('run-1');

      controller
          .historyLoaded(_history(_usage('run-1', finalInputTokens: 5000)));

      answer.complete(_usage('run-1', finalInputTokens: 5000));
      await pending;

      expect(banked, greaterThan(0));
      expect(controller.usage.tokens, 5000);
    });
  });

  group('an estimate a measurement cannot account for', () {
    test('survives an answer whose fetch predates the send', () async {
      // The fetch went out before this message was sent, so the count it
      // brings back cannot include it.
      final answer = Completer<RunUsage?>();
      when(() => api.getRunUsage(_roomId, _threadId, 'run-1'))
          .thenAnswer((_) => answer.future);
      final controller = build();

      final pending = controller.runEnded('run-1');
      controller.draftChanged('a message sent while the fetch was open');
      await Future<void>.delayed(Duration.zero);
      controller.draftSent('a message sent while the fetch was open');
      final banked = controller.usage.estimatedTokens;

      answer.complete(_usage('run-1', finalInputTokens: 5000));
      await pending;

      expect(banked, greaterThan(0));
      expect(controller.usage.tokens, 5000 + banked);
    });

    test('survives a history seed, which measured none of it', () async {
      // The history was fetched when the thread opened; a message sent
      // since is not in it.
      final controller = build()..draftChanged('a message on its way');
      await Future<void>.delayed(Duration.zero);
      controller.draftSent('a message on its way');
      final banked = controller.usage.estimatedTokens;

      controller
          .historyLoaded(_history(_usage('run-1', finalInputTokens: 1800)));

      expect(banked, greaterThan(0));
      expect(controller.usage.tokens, 1800 + banked);
    });
  });

  group('the draft', () {
    test('adds to the measurement', () async {
      final controller = build()
        ..historyLoaded(_history(_usage('run-1', finalInputTokens: 1000)))
        ..draftChanged('a draft with several words in it');
      await Future<void>.delayed(Duration.zero);

      expect(controller.usage.tokens, greaterThan(1000));
    });

    test('makes the reading no longer exact', () async {
      // The measurement is the provider's own count; the draft is not.
      final controller = build()
        ..historyLoaded(_history(_usage('run-1', finalInputTokens: 1000)));
      expect(controller.usage.isExact, isTrue);

      controller.draftChanged('unsent');
      await Future<void>.delayed(Duration.zero);

      expect(controller.usage.isExact, isFalse);
    });

    test('coalesces a burst of keystrokes into one reading', () async {
      final controller = build(debounce: const Duration(milliseconds: 20));
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller
        ..draftChanged('a')
        ..draftChanged('ab')
        ..draftChanged('abc');
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(notifications, 1);
    });

    test('sending holds the estimate until a run reports', () async {
      // Dropping it here would make the gauge read low for the whole
      // length of the run, which is the one direction it must not.
      final controller = build()
        ..historyLoaded(_history(_usage('run-1', finalInputTokens: 1000)))
        ..draftChanged('something being typed');
      await Future<void>.delayed(Duration.zero);
      final withDraft = controller.usage.tokens;

      controller.draftSent('something being typed');

      expect(controller.usage.tokens, withDraft);
      expect(controller.usage.isExact, isFalse);
    });

    test('the run\'s measurement releases the held estimate', () async {
      runAnswers('run-2', _usage('run-2', finalInputTokens: 1200));
      final controller = build()
        ..historyLoaded(_history(_usage('run-1', finalInputTokens: 1000)))
        ..draftChanged('something being typed');
      await Future<void>.delayed(Duration.zero);
      controller.draftSent('something being typed');

      await controller.runEnded('run-2');

      expect(controller.usage.tokens, 1200);
      expect(controller.usage.isExact, isTrue);
    });

    test('a run that measured nothing releases it too', () async {
      // Holding an estimate against a run that has ended would read
      // high for good. The message either never reached the model or is
      // inside the previous reading already.
      runAnswers('run-2', null);
      final controller = build()
        ..historyLoaded(_history(_usage('run-1', finalInputTokens: 1000)))
        ..draftChanged('something being typed');
      await Future<void>.delayed(Duration.zero);
      controller.draftSent('something being typed');

      await controller.runEnded('run-2');

      expect(controller.usage.tokens, 1000);
      expect(controller.usage.isExact, isTrue);
    });

    test('a failed fetch keeps it, because the message did reach the model',
        () async {
      // The measurement is what went missing, not the message. Dropping
      // the estimate here would move the reading *down* after a send —
      // the one direction it must never move.
      when(() => api.getRunUsage(_roomId, _threadId, 'run-2'))
          .thenThrow(const NetworkException(message: 'down'));
      final controller = build()
        ..historyLoaded(_history(_usage('run-1', finalInputTokens: 1000)))
        ..draftChanged('something being typed');
      await Future<void>.delayed(Duration.zero);
      final sent = controller.usage.tokens;
      controller.draftSent('something being typed');

      await controller.runEnded('run-2');

      expect(controller.usage.tokens, sent);
      expect(controller.usage.isExact, isFalse);
    });

    test('a later measurement clears the estimate the failure kept', () async {
      when(() => api.getRunUsage(_roomId, _threadId, 'run-2'))
          .thenThrow(const NetworkException(message: 'down'));
      runAnswers('run-3', _usage('run-3', finalInputTokens: 4000));
      final controller = build()
        ..historyLoaded(_history(_usage('run-1', finalInputTokens: 1000)))
        ..draftChanged('something being typed');
      await Future<void>.delayed(Duration.zero);
      controller.draftSent('something being typed');
      await controller.runEnded('run-2');

      await controller.runEnded('run-3');

      expect(controller.usage.tokens, 4000);
      expect(controller.usage.isExact, isTrue);
    });
  });

  group('a send that never reached a run', () {
    test('releases the estimate holding its place', () async {
      final controller = build()
        ..historyLoaded(_history(_usage('run-1', finalInputTokens: 1000)))
        ..draftChanged('something being typed');
      await Future<void>.delayed(Duration.zero);
      controller.draftSent('something being typed');
      expect(controller.usage.tokens, greaterThan(1000));

      controller.sendFailed();

      expect(controller.usage.tokens, 1000);
    });

    test('does not double-count once the composer restores the draft',
        () async {
      // The estimate and the restored draft are the same message. Nothing
      // will report on it, so the estimate has to come out before the
      // draft is counted again.
      final controller = build()
        ..historyLoaded(_history(_usage('run-1', finalInputTokens: 1000)))
        ..draftChanged('something being typed');
      await Future<void>.delayed(Duration.zero);
      final withDraft = controller.usage.tokens;
      controller.draftSent('something being typed');

      controller.sendFailed();
      controller.draftChanged('something being typed');
      await Future<void>.delayed(Duration.zero);

      expect(controller.usage.tokens, withDraft);
    });
  });

  test('a disposed controller stops answering', () async {
    final controller = build(debounce: const Duration(milliseconds: 20))
      ..dispose();

    controller
      ..draftChanged('typed after disposal')
      ..historyLoaded(_history(_usage('run-1', finalInputTokens: 10)));
    await Future<void>.delayed(const Duration(milliseconds: 60));

    // No notification is dispatched, which would throw on a disposed
    // ChangeNotifier; reaching here is the assertion.
    expect(controller.usage.tokens, isNull);
    expect(controller.usage.estimatedTokens, 0);
  });
}
