import 'dart:async';

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
// `soliplex_agent` hides `SoliplexApi` and `appendUserMessage`.
import 'package:soliplex_client/soliplex_client.dart'
    show SoliplexApi, appendUserMessage;
import 'package:soliplex_frontend/src/modules/room/context_usage_controller.dart';

class MockSoliplexApi extends Mock implements SoliplexApi {}

const _roomId = 'room-1';
const _threadId = 'thread-1';
const _noDebounce = Duration.zero;

RunUsage _usage(String runId, int finalInputTokens) => RunUsage(
      runId: runId,
      inputTokens: 9999,
      outputTokens: 1,
      requests: 1,
      toolCalls: 0,
      finalInputTokens: finalInputTokens,
    );

/// A transcript of one user message per text, as a send appends them.
Transcript _transcript(List<String> texts) => texts
    .fold(
      Conversation.empty(threadId: _threadId),
      (conversation, text) => appendUserMessage(
        conversation,
        TextMessage.create(id: 'u-$text', user: ChatUser.user, text: text),
      ),
    )
    .transcript;

ThreadHistory _history(
  List<String> texts, {
  RunUsage? measured,
  int covered = 0,
}) =>
    ThreadHistory(
      messages: const [],
      transcript: _transcript(texts),
      latestMeasurement: measured == null
          ? null
          : MeasuredRun(usage: measured, coveredMessages: covered),
    );

/// What the transcript of [texts] holds past its first [covered] messages.
int _after(List<String> texts, int covered) =>
    estimateTranscriptTokens(_transcript(texts).messages.skip(covered));

void main() {
  late MockSoliplexApi api;
  late Signal<int?> window;

  ContextUsageController build({int? windowSize = 8192, Duration? debounce}) {
    window = Signal<int?>(windowSize);
    final controller = ContextUsageController(
      api: api,
      roomId: _roomId,
      threadId: _threadId,
      contextWindow: window,
      draftDebounce: debounce ?? _noDebounce,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  void answers(String runId, Future<RunUsage?> Function() answer) {
    when(() => api.getRunUsage(_roomId, _threadId, runId))
        .thenAnswer((_) => answer());
  }

  setUp(() => api = MockSoliplexApi());

  test('offers no total before anything is measured', () {
    final controller = build()..sendStarted([const TextPart('hello')]);

    expect(controller.usage.value.tokens, isNull);
  });

  group('history', () {
    test('seeds the measurement it carries', () {
      final controller = build()
        ..historyLoaded(
            _history(['a'], measured: _usage('run-1', 1800), covered: 1));

      expect(controller.usage.value.tokens, 1800);
      expect(controller.usage.value.isExact, isTrue);
    });

    test('estimates what its transcript holds after the measurement', () {
      // Q2: a newer run that recorded no count still carried its messages.
      final texts = ['a', 'b', 'c'];
      expect(_after(texts, 1), greaterThan(0));

      final controller = build()
        ..historyLoaded(
            _history(texts, measured: _usage('run-1', 1800), covered: 1));

      expect(controller.usage.value.measuredTokens, 1800);
      expect(controller.usage.value.estimatedTokens, _after(texts, 1));
    });

    test('does not replace a longer transcript it is older than', () {
      final controller = build()
        ..historyLoaded(
            _history(['a', 'b'], measured: _usage('run-1', 1800), covered: 1))
        ..historyLoaded(
            _history(['a'], measured: _usage('run-1', 1800), covered: 1));

      expect(controller.usage.value.estimatedTokens, _after(['a', 'b'], 1));
    });
  });

  group('a send', () {
    ContextUsageController measured() => build()
      ..historyLoaded(
          _history(['a'], measured: _usage('run-1', 1000), covered: 1));

    test('is counted from the moment it is sent', () {
      final controller = measured()..sendStarted([const TextPart('hello')]);

      expect(
          controller.usage.value.estimatedTokens, estimateDraftTokens('hello'));
    });

    test('counts its images', () {
      final controller = measured()
        ..sendStarted([
          const TextPart('look'),
          ImagePart(bytes: Uint8List(0), mimeType: 'image/png'),
        ]);

      expect(controller.usage.value.estimatedTokens,
          estimateDraftTokens('look', images: 1));
    });

    test('is counted once its run starts, from the transcript', () {
      final controller = measured()
        ..sendStarted([const TextPart('hello')])
        ..runProgressed(_transcript(['a', 'hello']));

      expect(controller.usage.value.estimatedTokens, _after(['a', 'hello'], 1));
    });

    test('grows with its run\'s tool calls and results', () {
      // Live progress: the run's own later requests are where a window
      // overflows.
      final texts = ['a', 'hello', 'tool call', 'tool result'];
      final controller = measured()
        ..runProgressed(_transcript(['a', 'hello']))
        ..runProgressed(_transcript(texts));

      expect(controller.usage.value.estimatedTokens, _after(texts, 1));
    });

    test('ignores a transcript holding no more messages', () {
      // Streamed text replaces a message in place; re-estimating it per
      // token would buy nothing the run's end does not settle.
      final controller = measured()
        ..runProgressed(_transcript(['a', 'hello']))
        ..runProgressed(_transcript(['a', 'a much longer replacement']));

      expect(controller.usage.value.estimatedTokens, _after(['a', 'hello'], 1));
    });

    test('is covered by its run\'s count once the run completes', () async {
      answers('run-2', () async => _usage('run-2', 1500));
      final controller = measured()
        ..sendStarted([const TextPart('hello')])
        ..runProgressed(_transcript(['a', 'hello']));

      await controller.runCompleted('run-2', _transcript(['a', 'hello']));

      expect(controller.usage.value.tokens, 1500);
      expect(controller.usage.value.isExact, isTrue);
    });

    test('stays estimated when its run records no count', () async {
      answers('run-2', () async => null);
      final controller = measured()..runProgressed(_transcript(['a', 'hello']));

      await controller.runCompleted('run-2', _transcript(['a', 'hello']));

      expect(controller.usage.value.measuredTokens, 1000);
      expect(controller.usage.value.estimatedTokens, _after(['a', 'hello'], 1));
    });

    test('stays estimated when the count cannot be fetched', () async {
      answers(
          'run-2',
          () async => throw const NetworkException(
                message: 'offline',
              ));
      final controller = measured()..runProgressed(_transcript(['a', 'hello']));

      await controller.runCompleted('run-2', _transcript(['a', 'hello']));

      expect(controller.usage.value.estimatedTokens, _after(['a', 'hello'], 1));
    });
  });

  group('a send that ends without a count', () {
    ContextUsageController measured() => build()
      ..historyLoaded(
          _history(['a'], measured: _usage('run-1', 1000), covered: 1));

    test('keeps counting what its transcript carried forward', () {
      // D13 / D14: an errored run keeps what it streamed, a stopped one its
      // message; either way the next request carries it.
      final controller = measured()
        ..sendStarted([const TextPart('hello')])
        ..sendEnded(_transcript(['a', 'hello']));

      expect(controller.usage.value.estimatedTokens, _after(['a', 'hello'], 1));
    });

    test('takes a stopped run\'s shorter transcript', () {
      // A run cut off before its final state reverts to what it was sent.
      // A guard that kept the longer, live transcript would freeze the
      // reading high.
      final controller = measured()
        ..runProgressed(_transcript(['a', 'q', 'tool call', 'tool result']))
        ..sendEnded(_transcript(['a', 'q']));

      expect(controller.usage.value.estimatedTokens, _after(['a', 'q'], 1));
    });

    test('counts nothing when nothing was carried forward', () {
      // A spawn that failed or was cancelled before any run.
      final controller = measured()
        ..sendStarted([const TextPart('hello')])
        ..sendEnded(null);

      expect(controller.usage.value.estimatedTokens, 0);
    });
  });

  group('order', () {
    test('an older answer arriving late does not replace a newer count',
        () async {
      final older = Completer<RunUsage?>();
      answers('run-2', () => older.future);
      answers('run-3', () async => _usage('run-3', 3000));
      final controller = build()
        ..historyLoaded(
            _history(['a'], measured: _usage('run-1', 1000), covered: 1));

      final pending = controller.runCompleted('run-2', _transcript(['a', 'b']));
      await controller.runCompleted('run-3', _transcript(['a', 'b', 'c']));
      older.complete(_usage('run-2', 2000));
      await pending;

      expect(controller.usage.value.tokens, 3000);
    });

    test('a newer fetch that fails does not block an older answer', () async {
      // Q1.
      final older = Completer<RunUsage?>();
      answers('run-2', () => older.future);
      answers(
          'run-3',
          () async => throw const NetworkException(
                message: 'offline',
              ));
      final controller = build()
        ..historyLoaded(
            _history(['a'], measured: _usage('run-1', 1000), covered: 1));

      final pending = controller.runCompleted('run-2', _transcript(['a', 'b']));
      await controller.runCompleted('run-3', _transcript(['a', 'b', 'c']));
      older.complete(_usage('run-2', 2000));
      await pending;

      expect(controller.usage.value.measuredTokens, 2000);
      expect(
          controller.usage.value.estimatedTokens, _after(['a', 'b', 'c'], 2));
    });
  });

  group('draft', () {
    test('clearing it cancels a pending estimate at once', () async {
      final controller = build(debounce: const Duration(milliseconds: 300))
        ..historyLoaded(
            _history(['a'], measured: _usage('run-1', 1000), covered: 1))
        ..draftChanged('typed and sent inside the debounce window')
        ..draftChanged('');

      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(controller.usage.value.draftTokens, 0);
    });

    test('counts the draft once typing pauses', () async {
      final controller = build()
        ..historyLoaded(
            _history(['a'], measured: _usage('run-1', 1000), covered: 1))
        ..draftChanged('a draft');
      await Future<void>.delayed(Duration.zero);

      expect(
          controller.usage.value.draftTokens, estimateDraftTokens('a draft'));
      expect(controller.usage.value.estimatedTokens, 0);
    });
  });

  test('a window that arrives later moves the reading', () {
    final controller = build(windowSize: null)
      ..historyLoaded(
          _history(['a'], measured: _usage('run-1', 1800), covered: 1));
    expect(controller.usage.value.fractionUsed, isNull);

    window.value = 8192;

    expect(controller.usage.value.fractionUsed, closeTo(1800 / 8192, 1e-9));
  });

  group('warning', () {
    // 8192 is under 128k, so the threshold is 80%: 6554 tokens.
    ContextUsageController at(int tokens) => build()
      ..historyLoaded(
          _history(['a'], measured: _usage('run-1', tokens), covered: 1));

    test('is null while there is room', () {
      expect(at(1000).warning.value, isNull);
    });

    test('carries the reading once nearly full', () {
      expect(at(7000).warning.value?.tokens, 7000);
    });

    test('hides once the reading falls back under the threshold', () {
      // C2 at the source: the warning is derived, so nothing can skip it.
      final controller = at(6000)..sendStarted([TextPart('pad ' * 1000)]);
      expect(controller.warning.value, isNotNull);

      controller.sendEnded(null);

      expect(controller.warning.value, isNull);
    });

    test('stays hidden after dismissal while still nearly full', () {
      final controller = at(7000)..dismissWarning();

      expect(controller.warning.value, isNull);
    });

    test('returns after a dismissal once the reading dips and climbs again',
        () {
      final controller = at(6000)
        ..sendStarted([TextPart('pad ' * 1000)])
        ..dismissWarning();
      expect(controller.warning.value, isNull);

      controller
        ..sendEnded(null)
        ..sendStarted([TextPart('pad ' * 1000)]);

      expect(controller.warning.value, isNotNull);
    });
  });

  test('an answer after dispose writes nothing and does not throw', () async {
    final answer = Completer<RunUsage?>();
    answers('run-1', () => answer.future);
    final controller = ContextUsageController(
      api: api,
      roomId: _roomId,
      threadId: _threadId,
      contextWindow: Signal<int?>(8192),
      draftDebounce: _noDebounce,
    );

    final pending = controller.runCompleted('run-1', _transcript(['a']));
    controller.dispose();
    answer.complete(_usage('run-1', 1800));

    await expectLater(pending, completes);
  });
}
