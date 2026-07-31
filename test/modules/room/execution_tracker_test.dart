import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

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

  group('tool call detail', () {
    // The args and the result are attributes of the call the step row already
    // represents, so the tracker folds them onto that step rather than
    // nesting a second row under it.
    List<TimelineStep> steps() =>
        tracker.timeline.value.whereType<TimelineStep>().toList();

    test('thinking and client-tool steps carry no toolCallId', () {
      // Only a server tool call has args and a result to show, so only its
      // step is expandable. A null id is what makes the chevron absent.
      events.value = const ThinkingStarted();
      events.value = const ClientToolExecuting(
        toolName: 'local_tool',
        toolCallId: 'tc-client',
      );

      expect(steps().map((s) => s.toolCallId), [null, null]);
    });

    test('args deltas concatenate onto the step in arrival order', () {
      events.value = const ServerToolCallStarted(
        toolName: 'rag_search',
        toolCallId: 'tc-1',
      );
      events.value = const ServerToolCallArgs(
        toolCallId: 'tc-1',
        delta: '{"query":"pump ',
      );
      events.value = const ServerToolCallArgs(
        toolCallId: 'tc-1',
        delta: 'maintenance"}',
      );

      expect(steps().single.args, '{"query":"pump maintenance"}');
    });

    test('ServerToolCallCompleted attaches its result to the same call', () {
      events.value = const ServerToolCallStarted(
        toolName: 'rag_cite',
        toolCallId: 'tc-1',
      );
      events.value = const ServerToolCallCompleted(
        toolCallId: 'tc-1',
        result: 'Registered 2 citation(s).',
      );

      expect(steps().single.result, 'Registered 2 citation(s).');
      expect(steps().single.step.status, StepStatus.completed);
    });

    test('overlapping calls each settle their own step', () {
      // A toolset that does not declare itself sequential can overlap calls, so
      // both the detail and the completion must follow the id. Resolving either
      // by position puts one call's result or check mark on the other's row.
      events.value = const ServerToolCallStarted(
        toolName: 'run_python',
        toolCallId: 'tc-1',
      );
      events.value = const ServerToolCallStarted(
        toolName: 'run',
        toolCallId: 'tc-2',
      );
      events.value = const ServerToolCallArgs(
        toolCallId: 'tc-1',
        delta: '{"script":"print(1)"}',
      );
      events.value = const ServerToolCallCompleted(
        toolCallId: 'tc-1',
        result: 'first done',
      );

      final byId = {for (final s in steps()) s.toolCallId: s};
      expect(byId['tc-1']!.args, '{"script":"print(1)"}');
      expect(byId['tc-1']!.result, 'first done');
      expect(
        byId['tc-1']!.step.status,
        StepStatus.completed,
        reason: 'The call that returned is the one that should settle.',
      );
      expect(
        byId['tc-2']!.result,
        isNull,
        reason: 'tc-2 has not returned, so it must carry no result.',
      );
      expect(
        byId['tc-2']!.step.status,
        StepStatus.active,
        reason: 'Completing by position would settle tc-2 here instead.',
      );
    });

    test('a call id reused by a later run resolves to the later step', () {
      // The reload path buckets several runs' events into one tracker, so the
      // same id can open two steps. Detail must land on the one that opened
      // most recently, or the later run's args overwrite the earlier run's row.
      events.value = const ServerToolCallStarted(
        toolName: 'rag_search',
        toolCallId: 'tc-1',
      );
      events.value = const ServerToolCallArgs(
        toolCallId: 'tc-1',
        delta: '{"query":"first"}',
      );
      events.value = const ServerToolCallCompleted(
        toolCallId: 'tc-1',
        result: 'first result',
      );
      events.value = const RunCompleted();
      events.value = const ServerToolCallStarted(
        toolName: 'rag_search',
        toolCallId: 'tc-1',
      );
      events.value = const ServerToolCallArgs(
        toolCallId: 'tc-1',
        delta: '{"query":"second"}',
      );
      events.value = const ServerToolCallCompleted(
        toolCallId: 'tc-1',
        result: 'second result',
      );

      expect(
        steps().map((s) => s.args),
        ['{"query":"first"}', '{"query":"second"}'],
        reason: 'Resolving oldest-first would append both onto run 1.',
      );
      expect(steps().map((s) => s.result), ['first result', 'second result']);
    });

    test('detail for an unknown toolCallId is not applied to another step', () {
      // Without an observed TOOL_CALL_START there is no step to attach to. The
      // orphan must be discarded rather than landing on whichever step happens
      // to be present — here the thinking step.
      events.value = const ThinkingStarted();
      events.value = const ServerToolCallArgs(
        toolCallId: 'tc-missing',
        delta: '{"query":"orphan"}',
      );
      events.value = const ServerToolCallCompleted(
        toolCallId: 'tc-missing',
        result: 'orphan result',
      );

      expect(steps().single.args, isEmpty);
      expect(steps().single.result, isNull);
      expect(
        steps().single.step.status,
        StepStatus.active,
        reason: 'An orphan result must not credit an unrelated step with a '
            'check mark and an elapsed time it did not earn.',
      );
    });
  });

  group('lost tool call detail is reported', () {
    // These warnings are the only trace a dropped TOOL_CALL_ARGS or
    // TOOL_CALL_RESULT leaves, so they are asserted rather than assumed.
    const loggerName = 'execution_tracker_diagnostics';
    late _RecordingSink sink;
    late ExecutionTracker subject;

    setUp(() {
      sink = _RecordingSink(loggerName);
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));
      subject = ExecutionTracker(
        executionEvents: events,
        activities: activities,
        logger: testLogger(loggerName),
      );
      addTearDown(subject.dispose);
    });

    test('a run completing with no result for a call warns once', () {
      events.value = const ServerToolCallStarted(
        toolName: 'rag_search',
        toolCallId: 'tc-1',
      );
      events.value = const RunCompleted();

      final record = sink.warnings.single;
      expect(record.attributes['tools'], 'rag_search');
      expect(record.attributes['count'], 1);
    });

    test('a later run does not re-report an earlier run\'s gap', () {
      // A replay bucket holds several runs, and the scan covers the whole
      // timeline, so without per-id dedup run 1's gap is reported again at
      // every later run's completion.
      events.value = const ServerToolCallStarted(
        toolName: 'rag_search',
        toolCallId: 'tc-1',
      );
      events.value = const RunCompleted();
      events.value = const ServerToolCallStarted(
        toolName: 'rag_cite',
        toolCallId: 'tc-2',
      );
      events.value = const RunCompleted();

      expect(
        sink.warnings.map((r) => r.attributes['tools']),
        ['rag_search', 'rag_cite'],
        reason: "Run 2's report must name only run 2's call.",
      );
    });

    test('a call that returned a result is not reported', () {
      events.value = const ServerToolCallStarted(
        toolName: 'rag_search',
        toolCallId: 'tc-1',
      );
      events.value = const ServerToolCallCompleted(
        toolCallId: 'tc-1',
        result: '',
      );
      events.value = const RunCompleted();

      expect(
        sink.warnings,
        isEmpty,
        reason: 'An empty result body is a result, not a missing one.',
      );
    });

    test('an unmatched call is reported once per phase, not per delta', () {
      // The delta stream would flood the sink unthrottled, but a lost result
      // still has to be reported for an id whose args were already lost.
      for (var i = 0; i < 5; i++) {
        events.value = ServerToolCallArgs(
          toolCallId: 'tc-missing',
          delta: 'chunk$i',
        );
      }
      events.value = const ServerToolCallCompleted(
        toolCallId: 'tc-missing',
        result: 'orphan',
      );

      expect(
        sink.warnings.map((r) => r.attributes['phase']),
        ['args', 'result'],
      );
    });
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
        reason: 'Frozen tracker must not read the disposed source. The '
            'matched substring is signals_core 6.2.1\'s verbatim warning; '
            'a signals_core upgrade that rewords it would silently pass '
            'this test — revisit the matcher on signals upgrades.',
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

/// Captures records from one tracker's logger, ignoring the other traffic the
/// shared `LogManager` sees so assertions stay strict.
class _RecordingSink implements LogSink {
  _RecordingSink(this.loggerName);

  final String loggerName;
  final List<LogRecord> records = [];

  /// The lost-detail reports, separated from the per-call confirmation the
  /// tracker also logs at info level.
  List<LogRecord> get warnings =>
      records.where((r) => r.level == LogLevel.warning).toList();

  @override
  void write(LogRecord record) {
    if (record.loggerName == loggerName) records.add(record);
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}
