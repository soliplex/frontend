import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/tracker_registry.dart';

import 'package:soliplex_logging/soliplex_logging.dart'
    show LogLevel, LogRecord, LogSink;

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
        text: 'reply',
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
        text: 'reply',
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
        text: 'reply',
      ),
      events1,
      activities,
    );

    registry.onStreaming(
      const TextStreaming(
        messageId: 'msg-2',
        user: ChatUser.assistant,
        text: 'reply',
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
        text: 'reply',
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
        text: 'reply',
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
        text: 'reply',
      ),
      events,
      activities,
    );

    registry.onRunTerminated();

    registry.onStreaming(
      const TextStreaming(
        messageId: 'msg-2',
        user: ChatUser.assistant,
        text: 'reply',
      ),
      events,
      activities,
    );

    registry.dispose();
    expect(registry.trackers, isEmpty);
  });

  test('warns when a run ends with events no tile will render', () {
    // Everything that happens is meant to reach a band: a reply's, or the
    // tile synthesized for a run that said nothing. A gap left over is work
    // the user watched happen and will not find again.
    final sink = _RecordingSink('test');
    LogManager.instance.addSink(sink);
    addTearDown(() => LogManager.instance.removeSink(sink));

    registry.onStreaming(const AwaitingText(), events, activities);
    events.value = const ServerToolCallStarted(
      toolName: 'search',
      toolCallId: 'tc-1',
    );

    registry.onRunTerminated();

    expect(sink.bandWarnings.single.attributes['events'], 1);
  });

  test('drops the band a run ends without anything claiming', () {
    // claimOpenBand has already moved it onto a tile if one exists, and
    // nothing renders what is left, so keeping it only leaves the next run's
    // first band to overwrite it without saying so.
    registry.onStreaming(const AwaitingText(), events, activities);

    registry.onRunTerminated();

    expect(registry.trackers.keys, isEmpty);
  });

  test('does not warn when the run ends with nothing left over', () {
    // A band that reached a message, and an empty one opened after it, are
    // the ordinary end of a run: a warning here would bury the one above.
    final sink = _RecordingSink('test');
    LogManager.instance.addSink(sink);
    addTearDown(() => LogManager.instance.removeSink(sink));

    registry.onStreaming(const AwaitingText(), events, activities);
    events.value = const ServerToolCallStarted(
      toolName: 'search',
      toolCallId: 'tc-1',
    );
    registry.onStreaming(
      const TextStreaming(
        messageId: 'msg-1',
        user: ChatUser.assistant,
        text: 'the answer',
      ),
      events,
      activities,
    );
    registry.onStreaming(const AwaitingText(), events, activities);

    registry.onRunTerminated();

    expect(sink.bandWarnings, isEmpty);
  });

  group('a message that never speaks', () {
    /// Opens and closes a message that carries no text — what a response
    /// beginning with a tool call leaves in the stream.
    void declare(String messageId) {
      registry.onStreaming(
        TextStreaming(
          messageId: messageId,
          user: ChatUser.assistant,
          text: '',
        ),
        events,
        activities,
      );
      registry.onStreaming(const AwaitingText(), events, activities);
    }

    test('a message carrying only whitespace takes none either', () {
      registry.onStreaming(const AwaitingText(), events, activities);

      registry.onStreaming(
        const TextStreaming(
          messageId: 'decl-1',
          user: ChatUser.assistant,
          text: '  ',
        ),
        events,
        activities,
      );

      expect(registry.trackers.keys, equals([awaitingTrackerKey]));
    });

    test('hands the answer the tracker that watched the whole run', () {
      registry.onStreaming(const AwaitingText(), events, activities);
      final opened = registry.trackers[awaitingTrackerKey];

      declare('decl-1');
      registry.onStreaming(
        const TextStreaming(
          messageId: 'msg-2',
          user: ChatUser.assistant,
          text: 'The C-band transmitter',
        ),
        events,
        activities,
      );

      expect(registry.trackers.keys, ['msg-2']);
      expect(registry.trackers['msg-2'], same(opened));
      expect(opened!.isFrozen, isFalse);
    });
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
          text: 'reply',
        ),
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

  group('claimOpenBand', () {
    test('moves the awaiting tracker to the new key', () {
      registry.onStreaming(
        const AwaitingText(currentPhase: ThinkingPhase()),
        events,
        activities,
      );
      final awaitingTracker = registry.trackers[awaitingTrackerKey];

      registry.claimOpenBand('no-response-run-1');

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
      registry.claimOpenBand('no-response-run-1');

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

      registry.claimOpenBand(awaitingTrackerKey);

      expect(registry.trackers[awaitingTrackerKey], same(before));
    });

    test('safely no-ops when no awaiting tracker exists', () {
      // Synthesized message exists in the conversation but the awaiting
      // tracker was never created (or already disposed). Must not throw
      // and must not corrupt registry state.
      registry.claimOpenBand('no-response-run-1');

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

      registry.claimOpenBand('no-response-run-1');

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

  test('AwaitingText after a message speaks opens the next band', () {
    // A band is the stretch of work between one thing the assistant said and
    // the next, so the message that just spoke closes its own.
    registry.onStreaming(const AwaitingText(), events, activities);
    registry.onStreaming(
      const TextStreaming(
        messageId: 'msg-1',
        user: ChatUser.assistant,
        text: 'reply',
      ),
      events,
      activities,
    );

    registry.onStreaming(const AwaitingText(), events, activities);

    expect(registry.trackers['msg-1']!.isFrozen, isTrue);
    expect(registry.trackers[awaitingTrackerKey]!.isFrozen, isFalse);
  });

  test('work after a reply lands on the message that follows it', () {
    registry.onStreaming(const AwaitingText(), events, activities);
    registry.onStreaming(
      const TextStreaming(
        messageId: 'msg-1',
        user: ChatUser.assistant,
        text: 'Let me look that up.',
      ),
      events,
      activities,
    );
    registry.onStreaming(const AwaitingText(), events, activities);

    events.value = const ServerToolCallStarted(
      toolName: 'search',
      toolCallId: 'tc-1',
    );

    registry.onStreaming(
      const TextStreaming(
        messageId: 'msg-2',
        user: ChatUser.assistant,
        text: 'The answer.',
      ),
      events,
      activities,
    );

    expect(registry.trackers['msg-1']!.steps.value, isEmpty);
    expect(
      registry.trackers['msg-2']!.steps.value.map((s) => s.label),
      ['search'],
    );
  });
}

/// Captures this registry's log records, ignoring the other traffic the
/// shared `LogManager` sees.
class _RecordingSink implements LogSink {
  _RecordingSink(this.loggerName);

  final String loggerName;
  final List<LogRecord> records = [];

  /// The unclaimed-band reports specifically. The trackers this registry
  /// builds log through the same logger, so filtering by name alone would let
  /// one of their warnings answer for one of these.
  List<LogRecord> get bandWarnings => records
      .where(
        (r) =>
            r.level == LogLevel.warning && r.message.contains('no tile claims'),
      )
      .toList();

  @override
  void write(LogRecord record) {
    if (record.loggerName == loggerName) records.add(record);
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}
