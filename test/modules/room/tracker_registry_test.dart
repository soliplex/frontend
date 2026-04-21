import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/tracker_registry.dart';

void main() {
  late Signal<ExecutionEvent?> events;
  late TrackerRegistry registry;

  setUp(() {
    events = Signal<ExecutionEvent?>(null);
    registry = TrackerRegistry();
  });

  tearDown(() => registry.dispose());

  test('starts empty', () {
    expect(registry.trackers, isEmpty);
  });

  test('creates tracker on AwaitingText when idle', () {
    registry.onStreaming(
      const AwaitingText(currentActivity: ThinkingActivity()),
      events,
    );

    expect(registry.trackers, hasLength(1));
    expect(registry.trackers.containsKey(awaitingTrackerKey), isTrue);
  });

  test('re-keys awaiting tracker to message ID on TextStreaming', () {
    registry.onStreaming(
      const AwaitingText(currentActivity: ThinkingActivity()),
      events,
    );

    registry.onStreaming(
      const TextStreaming(
        messageId: 'msg-1',
        user: ChatUser.assistant,
        text: '',
      ),
      events,
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
    );

    registry.onStreaming(
      const TextStreaming(
        messageId: 'msg-2',
        user: ChatUser.assistant,
        text: '',
      ),
      events2,
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
    );

    final tracker = registry.trackers['msg-1'];

    registry.onStreaming(
      const TextStreaming(
        messageId: 'msg-1',
        user: ChatUser.assistant,
        text: 'more text',
      ),
      events,
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
    );

    registry.onRunTerminated();

    registry.onStreaming(
      const TextStreaming(
        messageId: 'msg-2',
        user: ChatUser.assistant,
        text: '',
      ),
      events,
    );

    registry.dispose();
    expect(registry.trackers, isEmpty);
  });

  group('seedHistorical', () {
    test('adds frozen trackers under their message ids', () {
      final historical = {
        'asst-1': ExecutionTracker.historical(events: const []),
        'asst-2': ExecutionTracker.historical(events: const []),
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
      );
      final live = registry.trackers['asst-1'];

      final historical = {
        'asst-1': ExecutionTracker.historical(events: const []),
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
        text: '',
      ),
      events,
    );

    registry.onStreaming(
      const AwaitingText(currentActivity: ThinkingActivity()),
      events,
    );

    // Should not create an awaiting tracker — msg-1 is still active
    expect(registry.trackers, hasLength(1));
    expect(registry.trackers.containsKey('msg-1'), isTrue);
    expect(registry.trackers.containsKey(awaitingTrackerKey), isFalse);
  });
}
