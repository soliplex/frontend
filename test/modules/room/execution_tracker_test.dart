import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/execution_step.dart';
import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/timeline_entry.dart';

import '../../helpers/test_logger.dart';

void main() {
  late Signal<ExecutionEvent?> events;
  late Signal<List<ActivityRecord>> activities;
  late ExecutionTracker tracker;

  setUp(() {
    events = Signal<ExecutionEvent?>(null);
    activities = Signal<List<ActivityRecord>>(const []);
    tracker = ExecutionTracker(
      executionEvents: events,
      activities: activities,
      logger: testLogger(),
    );
  });

  tearDown(() => tracker.dispose());

  test('starts with empty steps and no thinking', () {
    expect(tracker.steps.value, isEmpty);
    expect(tracker.thinkingBlocks.value, isEmpty);
    expect(tracker.isThinkingStreaming.value, isFalse);
  });

  test('ThinkingStarted adds an active thinking step', () {
    events.value = const ThinkingStarted();

    expect(tracker.steps.value.length, 1);
    expect(tracker.steps.value.first.label, 'Thinking');
    expect(tracker.steps.value.first.status, StepStatus.active);
    expect(tracker.isThinkingStreaming.value, isTrue);
  });

  test('ThinkingEnded without preceding ThinkingStarted is a no-op', () {
    // A ThinkingEnded that arrives without a matching ThinkingStarted
    // (e.g., reasoning message bridged with no start) must clear the
    // streaming flag without inventing a step.
    events.value = const ThinkingEnded();

    expect(tracker.steps.value, isEmpty);
    expect(tracker.isThinkingStreaming.value, isFalse);
  });

  test('ThinkingContent accumulates in current thinking block', () {
    events.value = const ThinkingStarted();
    events.value = const ThinkingContent(delta: 'Hello ');
    events.value = const ThinkingContent(delta: 'world');

    expect(tracker.thinkingBlocks.value, ['Hello world']);
  });

  test('multiple thinking phases create separate blocks', () {
    events.value = const ThinkingStarted();
    events.value = const ThinkingContent(delta: 'first');
    events.value = const ServerToolCallStarted(
      toolName: 'search',
      toolCallId: 'tc-1',
    );
    events.value = const ServerToolCallCompleted(
      toolCallId: 'tc-1',
      result: 'done',
    );
    events.value = const ThinkingStarted();
    events.value = const ThinkingContent(delta: 'second');

    expect(tracker.thinkingBlocks.value, ['first', 'second']);
  });

  test('ServerToolCallStarted completes previous step and adds new', () {
    events.value = const ThinkingStarted();
    events.value = const ServerToolCallStarted(
      toolName: 'search',
      toolCallId: 'tc-1',
    );

    expect(tracker.steps.value.length, 2);
    expect(tracker.steps.value[0].status, StepStatus.completed);
    expect(tracker.steps.value[0].label, 'Thinking');
    expect(tracker.steps.value[1].status, StepStatus.active);
    expect(tracker.steps.value[1].label, 'search');
    expect(tracker.isThinkingStreaming.value, isFalse);
  });

  test('ServerToolCallCompleted marks step completed', () {
    events.value = const ServerToolCallStarted(
      toolName: 'search',
      toolCallId: 'tc-1',
    );
    events.value = const ServerToolCallCompleted(
      toolCallId: 'tc-1',
      result: 'done',
    );

    expect(tracker.steps.value.length, 1);
    expect(tracker.steps.value.first.status, StepStatus.completed);
  });

  test('ClientToolExecuting adds a step', () {
    events.value = const ClientToolExecuting(
      toolName: 'calculator',
      toolCallId: 'tc-2',
    );

    expect(tracker.steps.value.length, 1);
    expect(tracker.steps.value.first.label, 'calculator');
    expect(tracker.steps.value.first.status, StepStatus.active);
  });

  test('ClientToolCompleted marks step completed', () {
    events.value = const ClientToolExecuting(
      toolName: 'calculator',
      toolCallId: 'tc-2',
    );
    events.value = const ClientToolCompleted(
      toolCallId: 'tc-2',
      result: '42',
      status: ToolCallStatus.completed,
    );

    expect(tracker.steps.value.first.status, StepStatus.completed);
  });

  test('RunCompleted marks all steps completed', () {
    events.value = const ThinkingStarted();
    events.value = const ServerToolCallStarted(
      toolName: 'search',
      toolCallId: 'tc-1',
    );
    events.value = const RunCompleted();

    for (final step in tracker.steps.value) {
      expect(step.status, StepStatus.completed);
    }
    expect(tracker.isThinkingStreaming.value, isFalse);
  });

  test('RunFailed marks all active steps as failed', () {
    events.value = const ThinkingStarted();
    events.value = const RunFailed(error: 'oops');

    for (final step in tracker.steps.value) {
      expect(step.status, StepStatus.failed);
    }
  });

  test('RunCancelled marks all active steps as failed', () {
    events.value = const ThinkingStarted();
    events.value = const RunCancelled();

    for (final step in tracker.steps.value) {
      expect(step.status, StepStatus.failed);
    }
  });

  test('freeze called twice is a no-op (idempotent)', () {
    events.value = const ThinkingStarted();
    tracker.freeze();
    expect(tracker.isFrozen, isTrue);

    expect(() => tracker.freeze(), returnsNormally);
    expect(tracker.isFrozen, isTrue);
  });

  test('freeze stops listening but preserves data', () {
    events.value = const ThinkingStarted();
    events.value = const ThinkingContent(delta: 'hello');
    tracker.freeze();

    // Data is preserved
    expect(tracker.steps.value.length, 1);
    expect(tracker.thinkingBlocks.value, ['hello']);
    expect(tracker.isFrozen, isTrue);

    // New events are ignored
    events.value = const ServerToolCallStarted(
      toolName: 'search',
      toolCallId: 'tc-1',
    );
    expect(tracker.steps.value.length, 1);
  });

  test('ActivitySnapshot does not affect steps or thinking', () {
    events.value = const ThinkingStarted();
    events.value = const ActivitySnapshot(
      messageId: 'rag:call_1',
      activityType: 'skill_tool_call',
      content: {'tool_name': 'search'},
    );

    expect(tracker.steps.value.length, 1);
    expect(tracker.steps.value.first.label, 'Thinking');
    expect(tracker.steps.value.first.status, StepStatus.active);
    expect(tracker.isThinkingStreaming.value, isTrue);
  });

  test('dispose stops listening to events', () {
    tracker.dispose();
    events.value = const ThinkingStarted();
    expect(tracker.steps.value, isEmpty);
  });

  group('skillToolCalls signal', () {
    test('starts empty', () {
      expect(tracker.skillToolCalls.value, isEmpty);
    });

    test('reflects the source activities signal in order', () {
      activities.value = const [
        ActivityRecord(
          messageId: 'rag:call_a',
          activityType: 'skill_tool_call',
          content: {'tool_name': 'ask', 'args': '{"q":"a"}'},
          timestamp: 1,
        ),
        ActivityRecord(
          messageId: 'rag:call_b',
          activityType: 'skill_tool_call',
          content: {'tool_name': 'search', 'args': '{"q":"b"}'},
          timestamp: 2,
        ),
      ];

      final calls = tracker.skillToolCalls.value;
      expect(calls.map((c) => c.toolName), ['ask', 'search']);
    });

    test('filters records that fail to decode as a skill_tool_* view', () {
      // Records that aren't skill_tool_call or skill_tool_result are
      // skipped — the tracker's `skillToolCalls` is a typed view, not
      // a passthrough.
      activities.value = const [
        ActivityRecord(
          messageId: 'plan:1',
          activityType: 'plan',
          content: {'steps': 3},
          timestamp: 1,
        ),
      ];

      expect(tracker.skillToolCalls.value, isEmpty);
    });

    test('freeze decouples the tracker from the source activities signal', () {
      // ThreadViewState._detachSession absorbs the live tracker into its
      // historical map and then lets the session — owner of the source
      // `conversationActivities` — auto-dispose. The absorbed tracker
      // must capture the activity list at freeze time and stop tracking
      // the source: later session-side mutations cannot reach the
      // historical view, and later session disposal cannot pollute reads
      // with "signal read after disposed" warnings.
      activities.value = const [
        ActivityRecord(
          messageId: 'rag:call_1',
          activityType: 'skill_tool_call',
          content: {'tool_name': 'ask', 'args': '{"q":"hi"}'},
          timestamp: 1,
        ),
      ];
      expect(tracker.skillToolCalls.value.single.toolName, 'ask');

      tracker.freeze();

      // Post-absorption, the session is free to mutate or dispose its
      // signals; the absorbed tracker must stay pinned to what it had at
      // freeze time.
      activities.value = const [
        ActivityRecord(
          messageId: 'rag:call_1',
          activityType: 'skill_tool_call',
          content: {'tool_name': 'ask', 'args': '{"q":"hi"}'},
          timestamp: 1,
        ),
        ActivityRecord(
          messageId: 'rag:call_2',
          activityType: 'skill_tool_call',
          content: {'tool_name': 'search', 'args': '{}'},
          timestamp: 2,
        ),
      ];
      expect(
        tracker.skillToolCalls.value.map((c) => c.messageId),
        ['rag:call_1'],
        reason: 'Frozen tracker must not pick up late mutations from the '
            'session-owned source signal.',
      );

      // Disposing the source is the final step of session teardown.
      // Reading the frozen tracker after disposal must not warn nor throw.
      final captured = <String>[];
      runZoned(
        () {
          activities.dispose();
          // Force read; signals_core warns via `print` if a disposed
          // signal is reached on this code path.
          expect(
            tracker.skillToolCalls.value.single.toolName,
            'ask',
          );
        },
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => captured.add(line),
        ),
      );
      expect(
        captured.where((l) => l.contains('read after disposed')),
        isEmpty,
        reason: 'Frozen tracker must not read the disposed source.',
      );
    });
  });

  group('timeline', () {
    test('empty on fresh tracker', () {
      expect(tracker.timeline.value, isEmpty);
    });

    test('step appended as TimelineStep with empty activities', () {
      events.value = const ThinkingStarted();

      expect(tracker.timeline.value, hasLength(1));
      final entry = tracker.timeline.value.single;
      expect(entry, isA<TimelineStep>());
      final step = entry as TimelineStep;
      expect(step.step.label, 'Thinking');
      expect(step.activityIds, isEmpty);
    });

    test('activity during active step nests under it', () {
      events.value = const ClientToolExecuting(
        toolName: 'execute_skill',
        toolCallId: 'tc-1',
      );
      activities.value = const [
        ActivityRecord(
          messageId: 'bwrap:call_1',
          activityType: 'skill_tool_call',
          content: {'tool_name': 'execute_script', 'args': '{}'},
          timestamp: 100,
        ),
      ];
      events.value = const ActivitySnapshot(
        messageId: 'bwrap:call_1',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'execute_script', 'args': '{}'},
        timestamp: 100,
      );

      expect(tracker.timeline.value, hasLength(1));
      final step = tracker.timeline.value.single as TimelineStep;
      expect(step.activityIds, ['bwrap:call_1']);
      expect(tracker.skillToolCalls.value.single.toolName, 'execute_script');
    });

    test('activity arriving with no active step is standalone', () {
      events.value = const ActivitySnapshot(
        messageId: 'bwrap:call_1',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'execute_script', 'args': '{}'},
        timestamp: 100,
      );

      expect(tracker.timeline.value, hasLength(1));
      expect(tracker.timeline.value.single, isA<TimelineStandaloneActivity>());
    });

    test(
        'activity after a completed step with no new active step is standalone',
        () {
      events.value = const ClientToolExecuting(
        toolName: 'execute_skill',
        toolCallId: 'tc-1',
      );
      events.value = const ClientToolCompleted(
        toolCallId: 'tc-1',
        result: 'ok',
        status: ToolCallStatus.completed,
      );
      events.value = const ActivitySnapshot(
        messageId: 'bwrap:call_1',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'execute_script', 'args': '{}'},
        timestamp: 100,
      );

      expect(tracker.timeline.value, hasLength(2));
      expect(tracker.timeline.value.last, isA<TimelineStandaloneActivity>());
    });

    test('multiple steps each get their own activities', () {
      events.value = const ClientToolExecuting(
        toolName: 'execute_skill',
        toolCallId: 'tc-1',
      );
      events.value = const ActivitySnapshot(
        messageId: 'bwrap:call_1',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'execute_script', 'args': '{}'},
        timestamp: 100,
      );
      events.value = const ClientToolCompleted(
        toolCallId: 'tc-1',
        result: 'ok',
        status: ToolCallStatus.completed,
      );
      events.value = const ClientToolExecuting(
        toolName: 'execute_skill',
        toolCallId: 'tc-2',
      );
      events.value = const ActivitySnapshot(
        messageId: 'bwrap:call_2',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'list_environments', 'args': '{}'},
        timestamp: 200,
      );
      events.value = const ActivitySnapshot(
        messageId: 'bwrap:call_3',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'execute_script', 'args': '{}'},
        timestamp: 201,
      );

      final tl = tracker.timeline.value;
      expect(tl, hasLength(2));
      expect((tl[0] as TimelineStep).activityIds, ['bwrap:call_1']);
      expect(
        (tl[1] as TimelineStep).activityIds,
        ['bwrap:call_2', 'bwrap:call_3'],
      );
    });

    test('replace updates nested activity in place', () {
      events.value = const ClientToolExecuting(
        toolName: 'execute_skill',
        toolCallId: 'tc-1',
      );
      activities.value = const [
        ActivityRecord(
          messageId: 'bwrap:call_1',
          activityType: 'skill_tool_call',
          content: {
            'tool_name': 'execute_script',
            'args': '{}',
            'status': 'in_progress',
          },
          timestamp: 100,
        ),
      ];
      events.value = const ActivitySnapshot(
        messageId: 'bwrap:call_1',
        activityType: 'skill_tool_call',
        content: {
          'tool_name': 'execute_script',
          'args': '{}',
          'status': 'in_progress',
        },
        timestamp: 100,
      );
      activities.value = const [
        ActivityRecord(
          messageId: 'bwrap:call_1',
          activityType: 'skill_tool_call',
          content: {
            'tool_name': 'execute_script',
            'args': '{}',
            'status': 'done',
          },
          timestamp: 150,
        ),
      ];
      events.value = const ActivitySnapshot(
        messageId: 'bwrap:call_1',
        activityType: 'skill_tool_call',
        content: {
          'tool_name': 'execute_script',
          'args': '{}',
          'status': 'done',
        },
        timestamp: 150,
      );

      final step = tracker.timeline.value.single as TimelineStep;
      expect(step.activityIds, ['bwrap:call_1']);
      expect(
          tracker.skillToolCalls.value.single.status, SkillToolCallStatus.done);
    });

    test('step completion updates status in timeline entry', () {
      events.value = const ClientToolExecuting(
        toolName: 'execute_skill',
        toolCallId: 'tc-1',
      );
      events.value = const ClientToolCompleted(
        toolCallId: 'tc-1',
        result: 'ok',
        status: ToolCallStatus.completed,
      );

      final step = tracker.timeline.value.single as TimelineStep;
      expect(step.step.status, StepStatus.completed);
    });
  });

  group('ExecutionTracker.historical', () {
    test('returns frozen tracker', () {
      final tracker = ExecutionTracker.historical(
        events: const [],
        activities: const [],
        logger: testLogger(),
      );
      expect(tracker.isFrozen, isTrue);
      tracker.dispose();
    });

    test('seeds steps from events', () {
      final tracker = ExecutionTracker.historical(
        events: const [
          ThinkingStarted(),
          ThinkingContent(delta: 'hello'),
          ServerToolCallStarted(toolName: 'search', toolCallId: 'tc-1'),
          ServerToolCallCompleted(toolCallId: 'tc-1', result: 'ok'),
          RunCompleted(),
        ],
        activities: const [],
        logger: testLogger(),
      );

      expect(tracker.steps.value.map((s) => s.label), ['Thinking', 'search']);
      expect(tracker.steps.value.every((s) => s.status.isTerminal), isTrue);
      expect(tracker.thinkingBlocks.value, ['hello']);
      tracker.dispose();
    });

    test('seeds activities under active step when present', () {
      final tracker = ExecutionTracker.historical(
        events: const [
          ClientToolExecuting(toolName: 'execute_skill', toolCallId: 'tc-1'),
          ActivitySnapshot(
            messageId: 'bwrap:call_1',
            activityType: 'skill_tool_call',
            content: {'tool_name': 'execute_script', 'args': '{}'},
            timestamp: 100,
          ),
        ],
        activities: const [
          ActivityRecord(
            messageId: 'bwrap:call_1',
            activityType: 'skill_tool_call',
            content: {'tool_name': 'execute_script', 'args': '{}'},
            timestamp: 100,
          ),
        ],
        logger: testLogger(),
      );

      final step = tracker.timeline.value.single as TimelineStep;
      expect(step.activityIds, ['bwrap:call_1']);
      expect(tracker.skillToolCalls.value.single.toolName, 'execute_script');
      tracker.dispose();
    });

    test('empty events list yields empty timeline', () {
      final tracker = ExecutionTracker.historical(
        events: const [],
        activities: const [],
        logger: testLogger(),
      );
      expect(tracker.steps.value, isEmpty);
      expect(tracker.timeline.value, isEmpty);
      tracker.dispose();
    });

    test(
        'events ending mid-thinking are finalized: no spinner, no '
        'active step', () {
      final tracker = ExecutionTracker.historical(
        events: const [
          ThinkingStarted(),
          ThinkingContent(delta: 'reasoning'),
        ],
        activities: const [],
        logger: testLogger(),
      );

      expect(tracker.isThinkingStreaming.value, isFalse);
      expect(tracker.steps.value.every((s) => s.status.isTerminal), isTrue);
      tracker.dispose();
    });
  });

  test('freeze mid-thinking clears spinner and completes active step', () {
    events.value = const ThinkingStarted();
    events.value = const ThinkingContent(delta: 'hello');

    expect(tracker.isThinkingStreaming.value, isTrue);
    expect(tracker.steps.value.single.status, StepStatus.active);

    tracker.freeze();

    expect(tracker.isThinkingStreaming.value, isFalse);
    expect(tracker.steps.value.single.status, StepStatus.completed);
  });
}

extension on StepStatus {
  bool get isTerminal =>
      this == StepStatus.completed || this == StepStatus.failed;
}
