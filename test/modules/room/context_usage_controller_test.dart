import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_frontend/src/modules/room/context_usage_controller.dart';

class MockSoliplexApi extends Mock implements SoliplexApi {}

const _roomId = 'room-1';
const _threadId = 'thread-1';
const _noDebounce = Duration.zero;

void main() {
  late MockSoliplexApi api;

  ContextUsageController build({Duration? debounce}) => ContextUsageController(
        api: api,
        roomId: _roomId,
        threadId: _threadId,
        draftDebounce: debounce ?? _noDebounce,
      );

  void answerWith(ThreadContext context) {
    when(
      () => api.getThreadContext(
        _roomId,
        _threadId,
        detail: any(named: 'detail'),
      ),
    ).thenAnswer((_) async => context);
  }

  setUp(() {
    api = MockSoliplexApi();
  });

  group('before anything is known', () {
    test('reads as unknown', () {
      expect(build().usage, const ContextUsage.unknown());
    });

    test('has no window, so no percentage can be shown', () {
      expect(build().usage.fractionUsed, isNull);
    });
  });

  group('refresh', () {
    test('adopts the measurement and the window', () async {
      answerWith(
        const ThreadContext(
          maxModelLen: 8192,
          modelName: 'qwen',
          measuredTokens: 1800,
          measuredAtRunId: 'run-1',
        ),
      );
      final controller = build();

      await controller.refresh();

      expect(controller.usage.tokens, 1800);
      expect(controller.usage.contextWindow, 8192);
      expect(controller.usage.fractionUsed, closeTo(1800 / 8192, 1e-9));
      expect(controller.usage.isExact, isTrue);
    });

    test('a provider with no window leaves the reading windowless', () async {
      // Ollama reports 'prompt_tokens' but no context length. A count
      // with no denominator must not become a percentage.
      answerWith(
        const ThreadContext(modelName: 'gpt-oss', measuredTokens: 582),
      );
      final controller = build();

      await controller.refresh();

      expect(controller.usage.tokens, 582);
      expect(controller.usage.contextWindow, isNull);
      expect(controller.usage.fractionUsed, isNull);
      expect(controller.usage.hasWindow, isFalse);
    });

    test('notifies once when the reading moves', () async {
      answerWith(const ThreadContext(maxModelLen: 8192, measuredTokens: 10));
      final controller = build();
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.refresh();

      expect(notifications, 1);
    });

    test('does not notify when the reading is unchanged', () async {
      answerWith(const ThreadContext(maxModelLen: 8192, measuredTokens: 10));
      final controller = build();
      await controller.refresh();
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.refresh();

      expect(notifications, 0);
    });

    test('keeps the last honest reading when the backend fails', () async {
      answerWith(const ThreadContext(maxModelLen: 8192, measuredTokens: 900));
      final controller = build();
      await controller.refresh();

      when(
        () => api.getThreadContext(
          _roomId,
          _threadId,
          detail: any(named: 'detail'),
        ),
      ).thenThrow(const NetworkException(message: 'down'));

      await controller.refresh();

      expect(controller.usage.tokens, 900);
    });

    test('a failure before any reading stays unknown', () async {
      when(
        () => api.getThreadContext(
          _roomId,
          _threadId,
          detail: any(named: 'detail'),
        ),
      ).thenThrow(const NetworkException(message: 'down'));
      final controller = build();

      await controller.refresh();

      expect(controller.usage, const ContextUsage.unknown());
    });
  });

  group('the draft', () {
    test('adds to the measurement', () async {
      answerWith(const ThreadContext(maxModelLen: 8192, measuredTokens: 1000));
      final controller = build();
      await controller.refresh();

      controller.draftChanged('a draft with several words in it');
      await Future<void>.delayed(Duration.zero);

      expect(controller.usage.tokens, greaterThan(1000));
    });

    test('makes the reading no longer exact', () async {
      // The measurement is the provider's own count; the draft is not.
      answerWith(const ThreadContext(maxModelLen: 8192, measuredTokens: 1000));
      final controller = build();
      await controller.refresh();
      expect(controller.usage.isExact, isTrue);

      controller.draftChanged('unsent');
      await Future<void>.delayed(Duration.zero);

      expect(controller.usage.isExact, isFalse);
    });

    test('shows before any run has been measured', () async {
      // A brand-new thread has no measurement, but what is being typed
      // still costs something.
      final controller = build();

      controller.draftChanged('the very first message');
      await Future<void>.delayed(Duration.zero);

      expect(controller.usage.tokens, greaterThan(0));
    });

    test('coalesces a burst of keystrokes into one reading', () async {
      final controller = build(
        debounce: const Duration(milliseconds: 20),
      );
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
      answerWith(
        const ThreadContext(
          maxModelLen: 8192,
          measuredTokens: 1000,
          measuredAtRunId: 'run-1',
        ),
      );
      final controller = build();
      await controller.refresh();
      controller.draftChanged('something being typed');
      await Future<void>.delayed(Duration.zero);
      final withDraft = controller.usage.tokens;

      controller.draftSent();

      expect(controller.usage.tokens, withDraft);
      expect(controller.usage.isExact, isFalse);
    });

    test('a newer run releases the held estimate', () async {
      answerWith(
        const ThreadContext(
          maxModelLen: 8192,
          measuredTokens: 1000,
          measuredAtRunId: 'run-1',
        ),
      );
      final controller = build();
      await controller.refresh();
      controller.draftChanged('something being typed');
      await Future<void>.delayed(Duration.zero);
      controller.draftSent();

      answerWith(
        const ThreadContext(
          maxModelLen: 8192,
          measuredTokens: 1200,
          measuredAtRunId: 'run-2',
        ),
      );
      await controller.refresh();

      expect(controller.usage.tokens, 1200);
      expect(controller.usage.isExact, isTrue);
    });

    test('a refresh finding the same run keeps the estimate held', () async {
      // A refresh can land before the run is recorded. Releasing then
      // would drop the sent message from the count entirely.
      answerWith(
        const ThreadContext(
          maxModelLen: 8192,
          measuredTokens: 1000,
          measuredAtRunId: 'run-1',
        ),
      );
      final controller = build();
      await controller.refresh();
      controller.draftChanged('something being typed');
      await Future<void>.delayed(Duration.zero);
      controller.draftSent();
      final held = controller.usage.tokens;

      await controller.refresh();

      expect(controller.usage.tokens, held);
    });
  });

  group('the breakdown', () {
    test('is empty until asked for in detail', () async {
      answerWith(const ThreadContext(maxModelLen: 8192, measuredTokens: 900));
      final controller = build();

      await controller.refresh();

      expect(controller.usage.byKind, isEmpty);
    });

    test('translates the wire names to segment kinds', () async {
      answerWith(
        const ThreadContext(
          maxModelLen: 8192,
          measuredTokens: 1000,
          tokensByKind: {
            'userText': 100,
            'assistantText': 200,
            'toolCallArguments': 50,
            'toolResult': 150,
            'overhead': 500,
          },
        ),
      );
      final controller = build();

      await controller.refresh(detail: true);

      expect(controller.usage.byKind, {
        SegmentKind.userText: 100,
        SegmentKind.assistantText: 200,
        SegmentKind.toolCallArguments: 50,
        SegmentKind.toolResult: 150,
        SegmentKind.overhead: 500,
      });
    });

    test('drops a kind it does not recognise', () async {
      // Dropping it loses a slice; folding it into a neighbour would
      // silently inflate that one instead, which reads as fact.
      answerWith(
        const ThreadContext(
          maxModelLen: 8192,
          measuredTokens: 1000,
          tokensByKind: {'userText': 100, 'somethingNew': 400},
        ),
      );
      final controller = build();

      await controller.refresh(detail: true);

      expect(controller.usage.byKind, {SegmentKind.userText: 100});
    });

    test('counts the draft as user text', () async {
      answerWith(
        const ThreadContext(
          maxModelLen: 8192,
          measuredTokens: 1000,
          tokensByKind: {'userText': 100, 'overhead': 900},
        ),
      );
      final controller = build();
      await controller.refresh(detail: true);

      controller.draftChanged('a draft being typed right now');
      await Future<void>.delayed(Duration.zero);

      expect(
        controller.usage.byKind[SegmentKind.userText],
        greaterThan(100),
      );
    });

    test('asks the backend for detail only when told to', () async {
      answerWith(const ThreadContext(measuredTokens: 1));
      final controller = build();

      await controller.refresh();
      await controller.refresh(detail: true);

      verify(() => api.getThreadContext(_roomId, _threadId, detail: false))
          .called(1);
      verify(() => api.getThreadContext(_roomId, _threadId, detail: true))
          .called(1);
    });
  });

  test('a disposed controller stops answering', () async {
    answerWith(const ThreadContext(maxModelLen: 8192, measuredTokens: 10));
    final controller = build(debounce: const Duration(milliseconds: 20))
      ..dispose();

    controller.draftChanged('typed after disposal');
    await Future<void>.delayed(const Duration(milliseconds: 60));

    // No notification is dispatched, which would throw on a disposed
    // ChangeNotifier; reaching here is the assertion.
    expect(controller.usage, const ContextUsage.unknown());
  });
}
