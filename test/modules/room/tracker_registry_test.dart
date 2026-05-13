import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

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

  test('starts empty', () {
    expect(registry.trackers, isEmpty);
  });

  test('creates tracker on AwaitingText when idle', () {
    registry.onStreaming(
      const AwaitingText(currentPhase: ThinkingPhase()),
      events,
      activities,
    );

    expect(registry.trackers, hasLength(1));
    expect(registry.trackers.containsKey(awaitingTrackerKey), isTrue);
  });

  test('re-keys awaiting tracker to message ID on TextStreaming', () {
    registry.onStreaming(
      const AwaitingText(currentPhase: ThinkingPhase()),
      events,
      activities,
    );

    registry.onStreaming(
      const TextStreaming(
        messageId: 'msg-1',
        user: ChatUser.assistant,
        text: '',
      ),
      events,
      activities,
    );

    expect(registry.trackers.containsKey(awaitingTrackerKey), isFalse);
    expect(registry.trackers.containsKey('msg-1'), isTrue);
    // Same tracker instance — not a new one
    expect(registry.trackers, hasLength(1));
  });

  test('creates new tracker on TextStreaming when idle', () {
    registry.onStreaming(
      const TextStreaming(
        messageId: 'msg-1',
        user: ChatUser.assistant,
        text: '',
      ),
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
        text: '',
      ),
      events1,
      activities,
    );

    registry.onStreaming(
      const TextStreaming(
        messageId: 'msg-2',
        user: ChatUser.assistant,
        text: '',
      ),
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
        text: '',
      ),
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
        text: '',
      ),
      events,
      activities,
    );

    registry.onRunTerminated();

    expect(registry.trackers['msg-1']!.isFrozen, isTrue);
  });

  test('onRunTerminated is safe when idle', () {
    registry.onRunTerminated();
    expect(registry.trackers, isEmpty);
  });

  test('dispose disposes all trackers', () {
    registry.onStreaming(
      const TextStreaming(
        messageId: 'msg-1',
        user: ChatUser.assistant,
        text: '',
      ),
      events,
      activities,
    );

    registry.onRunTerminated();

    registry.onStreaming(
      const TextStreaming(
        messageId: 'msg-2',
        user: ChatUser.assistant,
        text: '',
      ),
      events,
      activities,
    );

    registry.dispose();
    expect(registry.trackers, isEmpty);
  });

  group('seedHistorical', () {
    test('adds frozen trackers under their message ids', () {
      final historical = {
        'asst-1':
            ExecutionTracker.historical(events: const [], logger: testLogger()),
        'asst-2':
            ExecutionTracker.historical(events: const [], logger: testLogger()),
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
          text: '',
        ),
        events,
        activities,
      );
      final live = registry.trackers['asst-1'];

      final historical = {
        'asst-1':
            ExecutionTracker.historical(events: const [], logger: testLogger()),
      };
      registry.seedHistorical(historical);

      expect(registry.trackers['asst-1'], same(live));
    });
  });

  group('renameAwaitingTo', () {
    test('moves the awaiting tracker to the new key', () {
      registry.onStreaming(
        const AwaitingText(currentPhase: ThinkingPhase()),
        events,
        activities,
      );
      final awaitingTracker = registry.trackers[awaitingTrackerKey];

      registry.renameAwaitingTo('no-response-run-1');

      expect(registry.trackers.containsKey(awaitingTrackerKey), isFalse);
      expect(registry.trackers['no-response-run-1'], same(awaitingTracker));
    });

    test('moved tracker is the one frozen on subsequent onRunTerminated', () {
      // Verifies _activeId was rewritten from awaitingTrackerKey to the
      // synthesized id; otherwise _freezeActive would no-op (the awaiting
      // entry no longer exists under that key).
      registry.onStreaming(
        const AwaitingText(currentPhase: ThinkingPhase()),
        events,
        activities,
      );
      registry.renameAwaitingTo('no-response-run-1');

      registry.onRunTerminated();

      expect(registry.trackers['no-response-run-1']!.isFrozen, isTrue);
    });

    test('no-ops when the new key equals the awaiting sentinel', () {
      registry.onStreaming(
        const AwaitingText(currentPhase: ThinkingPhase()),
        events,
        activities,
      );
      final before = registry.trackers[awaitingTrackerKey];

      registry.renameAwaitingTo(awaitingTrackerKey);

      expect(registry.trackers[awaitingTrackerKey], same(before));
    });

    test('safely no-ops when no awaiting tracker exists', () {
      // Synthesized message exists in the conversation but the awaiting
      // tracker was never created (or already disposed). Must not throw
      // and must not corrupt registry state.
      registry.renameAwaitingTo('no-response-run-1');

      expect(registry.trackers, isEmpty);
    });

    test(
        'disposes the existing tracker when the target key already holds one '
        'so the loser does not leak its subscription', () {
      // seedHistorical declared "live always wins over historical", but
      // an unguarded overwrite at the target key would leak the loser's
      // subscription. Simulate the collision by seeding then renaming.
      final historicalEvents = Signal<ExecutionEvent?>(null);
      final historicalTracker = ExecutionTracker(
        executionEvents: historicalEvents,
        activities: activities,
        logger: testLogger(),
      );
      registry.seedHistorical({'no-response-run-1': historicalTracker});

      registry.onStreaming(
        const AwaitingText(currentPhase: ThinkingPhase()),
        events,
        activities,
      );
      final awaitingTracker = registry.trackers[awaitingTrackerKey];

      registry.renameAwaitingTo('no-response-run-1');

      expect(
        registry.trackers['no-response-run-1'],
        same(awaitingTracker),
        reason: 'the live awaiting tracker must win over the historical one',
      );
      expect(
        historicalTracker.isFrozen,
        isTrue,
        reason: 'the clobbered tracker must be disposed (which freezes it) '
            'so its subscription is released — without the cleanup the '
            'historical tracker silently retains its event listener',
      );
    });
  });

  test('ignores AwaitingText when tracker already active', () {
    registry.onStreaming(
      const TextStreaming(
        messageId: 'msg-1',
        user: ChatUser.assistant,
        text: '',
      ),
      events,
      activities,
    );

    registry.onStreaming(
      const AwaitingText(currentPhase: ThinkingPhase()),
      events,
      activities,
    );

    // Should not create an awaiting tracker — msg-1 is still active
    expect(registry.trackers, hasLength(1));
    expect(registry.trackers.containsKey('msg-1'), isTrue);
    expect(registry.trackers.containsKey(awaitingTrackerKey), isFalse);
  });
}
