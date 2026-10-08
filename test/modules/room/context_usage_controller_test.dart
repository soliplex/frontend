import 'dart:async';

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
// `soliplex_agent` hides `SoliplexApi` and `appendUserMessage`.
import 'package:soliplex_client/soliplex_client.dart'
    show SoliplexApi, appendUserMessage;
import 'package:soliplex_frontend/src/modules/room/context_usage_controller.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

class MockSoliplexApi extends Mock implements SoliplexApi {}

const _roomId = 'room-1';
const _threadId = 'thread-1';
const _noDebounce = Duration.zero;

RunUsage _usage(String runId, int finalInputTokens) => RunUsage(
      runId: runId,
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

  group('history', () {
    test('seeds the measurement it carries', () {
      final controller = build()
        ..historyLoaded(
            _history(['a'], measured: _usage('run-1', 1800), covered: 1));

      expect(controller.usage.value.tokens, 1800);
      expect(controller.usage.value.isExact, isTrue);
    });

    test('estimates what its transcript holds after the measurement', () {
      // A newer run that recorded no count still carried its messages.
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

    test('logs a failed fetch with its thread and status, not the server text',
        () async {
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));
      answers(
          'run-2',
          () async => throw const ApiException(
                message: 'Bad gateway',
                statusCode: 502,
                serverMessage: 'upstream said no',
                body: '<html>upstream said no</html>',
              ));
      final controller = measured()..runProgressed(_transcript(['a', 'hello']));

      await controller.runCompleted('run-2', _transcript(['a', 'hello']));

      final record = sink.records.singleWhere(
        (r) => r.message == 'Run usage fetch failed; the run stays estimated',
      );
      expect(record.attributes['threadId'], _threadId);
      expect(record.attributes['runId'], 'run-2');
      expect(record.attributes['statusCode'], 502);
      expect(record.error, isNull);
      expect(record.attributes.values.join(' '), isNot(contains('upstream')));
    });

    test('still logs a failed fetch that lands after the thread is left',
        () async {
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));
      final fetch = Completer<RunUsage?>();
      answers('run-2', () => fetch.future);
      final controller = measured();
      final before = sink.records.length;

      final completed =
          controller.runCompleted('run-2', _transcript(['a', 'hello']));
      controller.dispose();
      fetch.completeError(const NetworkException(message: 'offline'));
      await completed;

      expect(
        sink.records.skip(before).map((r) => r.message),
        ['Run usage fetch failed; the run stays estimated'],
      );
    });

    test('adopts nothing from a count that lands after the thread is left',
        () async {
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));
      final fetch = Completer<RunUsage?>();
      answers('run-2', () => fetch.future);
      final controller = measured();
      final before = sink.records.length;

      final completed =
          controller.runCompleted('run-2', _transcript(['a', 'hello']));
      controller.dispose();
      fetch.complete(_usage('run-2', 1500));
      await completed;

      expect(sink.records.skip(before), isEmpty);
    });
  });

  group('a measured run with no reply count', () {
    const message =
        'Measured run has no reply count; the reading omits the last reply';

    Iterable<LogRecord> captureWarnings() {
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));
      return sink.records.where((r) => r.message == message);
    }

    test('is logged with its thread and run when adopted', () async {
      final warnings = captureWarnings();
      answers('run-1', () async => _usage('run-1', 1000));
      final controller = build();

      await controller.runCompleted('run-1', _transcript(['a']));

      final record = warnings.single;
      expect(record.level, LogLevel.warning);
      expect(record.attributes, {'threadId': _threadId, 'runId': 'run-1'});
    });

    test('is not logged when the run has a reply count', () async {
      final warnings = captureWarnings();
      answers(
        'run-1',
        () async => const RunUsage(
          runId: 'run-1',
          finalInputTokens: 1000,
          finalOutputTokens: 50,
        ),
      );
      final controller = build();

      await controller.runCompleted('run-1', _transcript(['a']));

      expect(warnings, isEmpty);
    });

    test('is not logged when an older measurement is ignored', () async {
      final warnings = captureWarnings();
      answers('run-1', () async => _usage('run-1', 900));
      final controller = build()
        ..historyLoaded(
          _history(
            ['a', 'b'],
            measured: const RunUsage(
              runId: 'run-2',
              finalInputTokens: 1000,
              finalOutputTokens: 50,
            ),
            covered: 2,
          ),
        );

      await controller.runCompleted('run-1', _transcript(['a']));

      expect(warnings, isEmpty);
    });
  });

  group('a send that ends without a count', () {
    ContextUsageController measured() => build()
      ..historyLoaded(
          _history(['a'], measured: _usage('run-1', 1000), covered: 1));

    test('keeps counting what its transcript carried forward', () {
      // An errored run keeps what it streamed, a stopped one its
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
      // A failed fetch for a newer run leaves the order of answers alone:
      // the older run's count still lands when it arrives.
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

    test('counts its images, which carry no text', () async {
      final controller = build()
        ..historyLoaded(
            _history(['a'], measured: _usage('run-1', 1000), covered: 1))
        ..draftChanged('', images: 1);
      await Future<void>.delayed(Duration.zero);

      expect(controller.usage.value.draftTokens,
          estimateDraftTokens('', images: 1));
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
      // The warning is derived from the reading, so no path that lowers the
      // reading can leave it showing.
      final controller = at(6000)..sendStarted([TextPart('pad ' * 1000)]);
      expect(controller.warning.value, isNotNull);

      controller.sendEnded(null);

      expect(controller.warning.value, isNull);
    });

    test('stays hidden after dismissal while still nearly full', () {
      final controller = at(7000)..dismissWarning();

      expect(controller.warning.value, isNull);
    });

    test('returns after a nearly-full dismissal once a draft fills the window',
        () async {
      final controller = at(7000)
        ..dismissWarning()
        ..draftChanged('pad ' * 2000);
      await Future<void>.delayed(Duration.zero);
      expect(controller.usage.value.level, ContextLevel.full,
          reason: 'precondition: the draft carries the reading over');

      expect(controller.warning.value, isNotNull);
    });

    test('stays hidden after a dismissal when the reading dips and climbs back',
        () async {
      final controller = at(6000)..draftChanged('pad ' * 1000);
      await Future<void>.delayed(Duration.zero);
      expect(controller.usage.value.level, ContextLevel.nearlyFull,
          reason: 'precondition: the draft carries the reading past 80%');
      controller
        ..dismissWarning()
        ..draftChanged('');
      expect(controller.usage.value.level, ContextLevel.room);

      controller.draftChanged('pad ' * 1000);
      await Future<void>.delayed(Duration.zero);
      expect(controller.usage.value.level, ContextLevel.nearlyFull,
          reason: 'precondition: the reading climbed back');

      expect(controller.warning.value, isNull);
    });

    test('returns after a dismissal once a message is sent', () {
      final controller = at(7000)
        ..dismissWarning()
        ..sendStarted([TextPart('short')]);
      expect(controller.usage.value.level, ContextLevel.nearlyFull);

      expect(controller.warning.value, isNotNull);
    });
  });
}
