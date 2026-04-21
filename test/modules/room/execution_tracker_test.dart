import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/execution_step.dart';
import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/timeline_entry.dart';

void main() {
  late Signal<ExecutionEvent?> events;
  late ExecutionTracker tracker;

  setUp(() {
    events = Signal<ExecutionEvent?>(null);
    tracker = ExecutionTracker(executionEvents: events);
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

    test('decodes a single skill_tool_call snapshot', () {
      events.value = const ActivitySnapshot(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_call',
        content: {
          'tool_name': 'ask',
          'args': '{"q":"hi"}',
          'status': 'in_progress',
        },
        timestamp: 100,
      );

      final calls = tracker.skillToolCalls.value;
      expect(calls, hasLength(1));
      expect(calls.single.messageId, 'rag:call_1');
      expect(calls.single.toolName, 'ask');
      expect(calls.single.args, {'q': 'hi'});
      expect(calls.single.status, 'in_progress');
      expect(calls.single.timestamp, 100);
    });

    test('replace:true overwrites record with same messageId in place', () {
      events.value = const ActivitySnapshot(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_call',
        content: {
          'tool_name': 'ask',
          'args': '{"q":"hi"}',
          'status': 'in_progress',
        },
        timestamp: 1,
      );
      events.value = const ActivitySnapshot(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_call',
        content: {
          'tool_name': 'ask',
          'args': '{"q":"hi"}',
          'status': 'done',
        },
        timestamp: 2,
      );

      final calls = tracker.skillToolCalls.value;
      expect(calls, hasLength(1));
      expect(calls.single.status, 'done');
      expect(calls.single.timestamp, 2);
    });

    test('replace:false on existing messageId is ignored', () {
      events.value = const ActivitySnapshot(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_call',
        content: {
          'tool_name': 'ask',
          'args': '{"q":"first"}',
          'status': 'in_progress',
        },
        timestamp: 1,
      );
      events.value = const ActivitySnapshot(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_call',
        content: {
          'tool_name': 'search',
          'args': '{"q":"second"}',
          'status': 'done',
        },
        replace: false,
        timestamp: 2,
      );

      final calls = tracker.skillToolCalls.value;
      expect(calls, hasLength(1));
      expect(calls.single.toolName, 'ask');
      expect(calls.single.args, {'q': 'first'});
    });

    test('two concurrent messageIds stay independent', () {
      events.value = const ActivitySnapshot(
        messageId: 'rag:call_a',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'ask', 'args': '{"q":"a"}'},
        timestamp: 1,
      );
      events.value = const ActivitySnapshot(
        messageId: 'rag:call_b',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'search', 'args': '{"q":"b"}'},
        timestamp: 2,
      );

      final calls = tracker.skillToolCalls.value;
      expect(calls, hasLength(2));
      final byId = {for (final c in calls) c.messageId: c};
      expect(byId['rag:call_a']!.toolName, 'ask');
      expect(byId['rag:call_b']!.toolName, 'search');
    });

    test('non-skill_tool_call activityType is dropped', () {
      events.value = const ActivitySnapshot(
        messageId: 'plan:1',
        activityType: 'plan',
        content: {'steps': 3},
        timestamp: 1,
      );

      expect(tracker.skillToolCalls.value, isEmpty);
    });

    test('malformed skill_tool_call is dropped', () {
      events.value = const ActivitySnapshot(
        messageId: 'rag:bad',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'ask', 'args': 'not json {'},
        timestamp: 1,
      );

      expect(tracker.skillToolCalls.value, isEmpty);
    });

    test(
      'missing timestamp is filled with wall-clock (non-zero) so the '
      'decoded activity still appears',
      () {
        events.value = const ActivitySnapshot(
          messageId: 'rag:call_1',
          activityType: 'skill_tool_call',
          content: {'tool_name': 'ask', 'args': '{}'},
        );

        final calls = tracker.skillToolCalls.value;
        expect(calls, hasLength(1));
        expect(calls.single.timestamp, greaterThan(0));
      },
    );
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
      expect(step.activities, isEmpty);
    });

    test('activity during active step nests under it', () {
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

      expect(tracker.timeline.value, hasLength(1));
      final step = tracker.timeline.value.single as TimelineStep;
      expect(step.activities, hasLength(1));
      expect(step.activities.single.toolName, 'execute_script');
    });

    test('activity arriving with no active step is an orphan', () {
      events.value = const ActivitySnapshot(
        messageId: 'bwrap:call_1',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'execute_script', 'args': '{}'},
        timestamp: 100,
      );

      expect(tracker.timeline.value, hasLength(1));
      expect(tracker.timeline.value.single, isA<TimelineOrphanActivity>());
    });

    test('activity after a completed step with no new active step is orphan',
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
      expect(tracker.timeline.value.last, isA<TimelineOrphanActivity>());
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
      expect((tl[0] as TimelineStep).activities, hasLength(1));
      expect((tl[1] as TimelineStep).activities, hasLength(2));
    });

    test('replace updates nested activity in place', () {
      events.value = const ClientToolExecuting(
        toolName: 'execute_skill',
        toolCallId: 'tc-1',
      );
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
      expect(step.activities, hasLength(1));
      expect(step.activities.single.status, 'done');
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
      final tracker = ExecutionTracker.historical(events: const []);
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
      );

      final step = tracker.timeline.value.single as TimelineStep;
      expect(step.activities, hasLength(1));
      expect(step.activities.single.toolName, 'execute_script');
      tracker.dispose();
    });

    test('empty events list yields empty timeline', () {
      final tracker = ExecutionTracker.historical(events: const []);
      expect(tracker.steps.value, isEmpty);
      expect(tracker.timeline.value, isEmpty);
      tracker.dispose();
    });
  });
}

extension on StepStatus {
  bool get isTerminal =>
      this == StepStatus.completed || this == StepStatus.failed;
}
