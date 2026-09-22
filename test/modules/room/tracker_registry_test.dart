import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/execution_step.dart';
import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/tracker_registry.dart';

import '../../helpers/test_logger.dart';

void main() {
  late Signal<ExecutionEvent?> events;
  late Signal<List<ActivityRecord>> activities;
  late TrackerRegistry registry;

  setUp(() {
    events = Signal<ExecutionEvent?>(null);
    activities = Signal<List<ActivityRecord>>(const []);
    registry = TrackerRegistry(logger: testLogger());
  });

  tearDown(() => registry.dispose());

  group("work stays with the run that did it", () {
    void awaiting() => registry.onStreaming(
          const AwaitingText(currentPhase: ThinkingPhase()),
          'run-0',
          events,
          activities,
        );
    void speaking(String id) => registry.onStreaming(
          TextStreaming(
            messageId: id,
            user: ChatUser.assistant,
            text: 'Answer.',
          ),
          'run-0',
          events,
          activities,
        );

    test('a terminated run does not hand its band to the next run', () {
      awaiting();
      events.value = const ThinkingStarted();
      registry.onRunTerminated(StepStatus.completed);

      awaiting();
      speaking('m1');

      expect(
        registry.trackers['m1']!.timeline.value,
        isEmpty,
        reason: "the previous run's work must not appear above this answer",
      );
    });

    test(
        'a second band in one run does not inherit the first one\'s last '
        'event', () {
      speaking('m1');
      events.value = const ThinkingStarted();
      speaking('m2');

      expect(
        registry.trackers['m2']!.timeline.value,
        isEmpty,
        reason: "m1's work belongs to m1",
      );
    });

    test('a band still keeps the work done after it opened', () {
      awaiting();
      events.value = const ThinkingStarted();
      registry.onRunTerminated(StepStatus.completed);

      awaiting();
      speaking('m1');
      events.value = const ServerToolCallStarted(
        toolCallId: 'c-1',
        toolName: 'search',
      );

      expect(registry.trackers['m1']!.timeline.value, hasLength(1));
    });
  });

  test('starts empty', () {
    expect(registry.trackers, isEmpty);
  });

  test('creates tracker on AwaitingText when idle', () {
    registry.onStreaming(
      const AwaitingText(currentPhase: ThinkingPhase()),
      'run-0',
      events,
      activities,
    );

    expect(registry.trackers, hasLength(1));
    expect(registry.trackers.containsKey(noResponseMessageId('run-0')), isTrue);
  });

  test('re-keys awaiting tracker to message ID on TextStreaming', () {
    registry.onStreaming(
      const AwaitingText(currentPhase: ThinkingPhase()),
      'run-0',
      events,
      activities,
    );

    registry.onStreaming(
      const TextStreaming(
        messageId: 'msg-1',
        user: ChatUser.assistant,
        text: 'Answer.',
      ),
      'run-0',
      events,
      activities,
    );

    expect(
        registry.trackers.containsKey(noResponseMessageId('run-0')), isFalse);
    expect(registry.trackers.containsKey('msg-1'), isTrue);
    // Same tracker instance — not a new one
    expect(registry.trackers, hasLength(1));
  });

  test('creates new tracker on TextStreaming when idle', () {
    registry.onStreaming(
      const TextStreaming(
        messageId: 'msg-1',
        user: ChatUser.assistant,
        text: 'Answer.',
      ),
      'run-0',
      events,
      activities,
    );

    expect(registry.trackers, hasLength(1));
    expect(registry.trackers.containsKey('msg-1'), isTrue);
  });

  test('freezes old tracker when new message starts streaming', () {
    final events1 = Signal<ExecutionEvent?>(null);
    final events2 = Signal<ExecutionEvent?>(null);

    registry.onStreaming(
      const TextStreaming(
        messageId: 'msg-1',
        user: ChatUser.assistant,
        text: 'Answer.',
      ),
      'run-0',
      events1,
      activities,
    );

    registry.onStreaming(
      const TextStreaming(
        messageId: 'msg-2',
        user: ChatUser.assistant,
        text: 'Answer.',
      ),
      'run-0',
      events2,
      activities,
    );

    expect(registry.trackers, hasLength(2));
    expect(registry.trackers['msg-1']!.isFrozen, isTrue);
    expect(registry.trackers['msg-2']!.isFrozen, isFalse);
  });

  test('no-ops when same message ID streams again', () {
    registry.onStreaming(
      const TextStreaming(
        messageId: 'msg-1',
        user: ChatUser.assistant,
        text: 'Answer.',
      ),
      'run-0',
      events,
      activities,
    );

    final tracker = registry.trackers['msg-1'];

    registry.onStreaming(
      const TextStreaming(
        messageId: 'msg-1',
        user: ChatUser.assistant,
        text: 'more text',
      ),
      'run-0',
      events,
      activities,
    );

    expect(registry.trackers, hasLength(1));
    expect(registry.trackers['msg-1'], same(tracker));
    expect(tracker!.isFrozen, isFalse);
  });

  test('freezes active tracker on run terminated', () {
    registry.onStreaming(
      const TextStreaming(
        messageId: 'msg-1',
        user: ChatUser.assistant,
        text: 'Answer.',
      ),
      'run-0',
      events,
      activities,
    );

    registry.onRunTerminated(StepStatus.completed);

    expect(registry.trackers['msg-1']!.isFrozen, isTrue);
  });

  test('onRunTerminated is safe when idle', () {
    registry.onRunTerminated(StepStatus.completed);
    expect(registry.trackers, isEmpty);
  });

  test('dispose disposes all trackers', () {
    registry.onStreaming(
      const TextStreaming(
        messageId: 'msg-1',
        user: ChatUser.assistant,
        text: 'Answer.',
      ),
      'run-0',
      events,
      activities,
    );

    registry.onRunTerminated(StepStatus.completed);

    registry.onStreaming(
      const TextStreaming(
        messageId: 'msg-2',
        user: ChatUser.assistant,
        text: 'Answer.',
      ),
      'run-0',
      events,
      activities,
    );

    registry.dispose();
    expect(registry.trackers, isEmpty);
  });

  group('seedHistorical', () {
    test('adds frozen trackers under their message ids', () {
      final historical = {
        'asst-1': ExecutionTracker.historical(
          origin: null,
          events: const [],
          activities: const [],
          logger: testLogger(),
        ),
        'asst-2': ExecutionTracker.historical(
          origin: null,
          events: const [],
          activities: const [],
          logger: testLogger(),
        ),
      };

      registry.seedHistorical(historical);

      expect(registry.trackers.keys, containsAll(['asst-1', 'asst-2']));
      expect(registry.trackers['asst-1']!.isFrozen, isTrue);
    });

    test('does not overwrite an existing live tracker', () {
      registry.onStreaming(
        const TextStreaming(
          messageId: 'asst-1',
          user: ChatUser.assistant,
          text: 'Answer.',
        ),
        'run-0',
        events,
        activities,
      );
      final live = registry.trackers['asst-1'];

      final historical = {
        'asst-1': ExecutionTracker.historical(
          origin: null,
          events: const [],
          activities: const [],
          logger: testLogger(),
        ),
      };
      registry.seedHistorical(historical);

      expect(registry.trackers['asst-1'], same(live));
    });
  });

  test('ignores AwaitingText when tracker already active', () {
    registry.onStreaming(
      const TextStreaming(
        messageId: 'msg-1',
        user: ChatUser.assistant,
        text: 'Answer.',
      ),
      'run-0',
      events,
      activities,
    );

    registry.onStreaming(
      const AwaitingText(currentPhase: ThinkingPhase()),
      'run-0',
      events,
      activities,
    );

    // Should not create an awaiting tracker — msg-1 is still active
    expect(registry.trackers, hasLength(1));
    expect(registry.trackers.containsKey('msg-1'), isTrue);
    expect(
        registry.trackers.containsKey(noResponseMessageId('run-0')), isFalse);
  });
}
