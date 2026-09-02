import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../../../../helpers/test_logger.dart';

import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/message_expansions.dart';
import 'package:soliplex_frontend/src/modules/room/room_providers.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/execution_timeline.dart';
import 'package:soliplex_frontend/src/modules/room/compute_display_messages.dart'
    show loadingMessageId;

const _roomId = 'r1';
const _messageId = 'm1';

void main() {
  late Signal<ExecutionEvent?> events;
  late Signal<List<ActivityRecord>> activities;
  late ExecutionTracker tracker;
  late MessageExpansions store;

  setUp(() {
    events = Signal<ExecutionEvent?>(null);
    activities = Signal<List<ActivityRecord>>(const []);
    tracker = ExecutionTracker(
      executionEvents: events,
      activities: activities,
      logger: testLogger(),
    );
    store = MessageExpansions();
  });

  // Helper: push an ActivitySnapshot event AND the corresponding
  // ActivityRecord into the activities signal, mirroring what
  // `_processActivitySnapshot` + the bridge do in production.
  void pushSnapshot({
    required String messageId,
    required String activityType,
    required Map<String, dynamic> content,
    required int timestamp,
    bool replace = true,
  }) {
    final record = ActivityRecord(
      messageId: messageId,
      activityType: activityType,
      content: content,
      timestamp: timestamp,
    );
    final idx = activities.value.indexWhere((a) => a.messageId == messageId);
    if (idx >= 0) {
      if (replace) {
        activities.value = [...activities.value]..[idx] = record;
      }
    } else {
      activities.value = [...activities.value, record];
    }
    events.value = ActivitySnapshot(
      messageId: messageId,
      activityType: activityType,
      content: content,
      timestamp: timestamp,
      replace: replace,
    );
  }

  tearDown(() => tracker.dispose());

  // Scrollable because the timeline lives inside the message list in
  // production; without one, an expanded source block overflows the test
  // viewport and the rendering assertion masks what is being asserted.
  Widget wrap(Widget child, {MessageExpansions? storeOverride}) =>
      ProviderScope(
        overrides: [
          messageExpansionsProvider.overrideWithValue(storeOverride ?? store),
        ],
        child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );

  ExecutionTimeline build({
    String roomId = _roomId,
    String messageId = _messageId,
    ExecutionTracker? t,
  }) =>
      ExecutionTimeline(
        roomId: roomId,
        messageId: messageId,
        tracker: t ?? tracker,
      );

  testWidgets('renders nothing for empty timeline', (tester) async {
    await tester.pumpWidget(wrap(build()));
    await tester.pump();

    expect(find.byType(GestureDetector), findsNothing);
  });

  testWidgets(
    'dangling activity id (in timeline but not in activities) renders '
    'as an empty row instead of throwing',
    (tester) async {
      // Place the activity on the timeline by firing an ActivitySnapshot
      // event, then clear the activities signal so the id resolves to
      // nothing. The renderer must fall through to SizedBox.shrink() for
      // the dangling id rather than throw on the missing lookup: an id and
      // its record arrive by two independent routes, so either can be
      // present without the other.
      events.value = const ClientToolExecuting(
        toolName: 'execute_skill',
        toolCallId: 'tc-1',
      );
      pushSnapshot(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'lookup', 'args': '{}'},
        timestamp: 100,
      );
      // Drop the activity record while the timeline retains the id.
      activities.value = const [];

      await tester.pumpWidget(wrap(build()));
      await tester.pump();
      // Expand the timeline so the row is built.
      await tester.tap(find.text('2 events'));
      await tester.pump();

      // The step row renders (it's a structural entry, not content-keyed).
      expect(find.text('execute_skill'), findsOneWidget);
      // The activity row does not render — no `lookup` text, no throw.
      expect(find.text('lookup'), findsNothing);
    },
  );

  testWidgets('header counts step + nested activities', (tester) async {
    events.value = const ClientToolExecuting(
      toolName: 'execute_skill',
      toolCallId: 'tc-1',
    );
    pushSnapshot(
      messageId: 'bwrap:call_1',
      activityType: 'skill_tool_call',
      content: {'tool_name': 'execute_script', 'args': '{}'},
      timestamp: 100,
    );
    pushSnapshot(
      messageId: 'bwrap:call_2',
      activityType: 'skill_tool_call',
      content: {'tool_name': 'list_environments', 'args': '{}'},
      timestamp: 101,
    );

    await tester.pumpWidget(wrap(build()));
    await tester.pump();

    expect(find.text('3 events'), findsOneWidget);
  });

  testWidgets('singular label when only one event', (tester) async {
    events.value = const ThinkingStarted();

    await tester.pumpWidget(wrap(build()));
    await tester.pump();

    expect(find.text('1 event'), findsOneWidget);
  });

  testWidgets('tap expands to show step and nested activity', (tester) async {
    events.value = const ClientToolExecuting(
      toolName: 'execute_skill',
      toolCallId: 'tc-1',
    );
    pushSnapshot(
      messageId: 'bwrap:call_1',
      activityType: 'skill_tool_call',
      content: {'tool_name': 'execute_script', 'args': '{}'},
      timestamp: 100,
    );

    await tester.pumpWidget(wrap(build()));
    await tester.pump();

    expect(find.text('execute_skill'), findsNothing);
    expect(find.text('execute_script'), findsNothing);

    await tester.tap(find.text('2 events'));
    await tester.pump();

    expect(find.text('execute_skill'), findsOneWidget);
    expect(find.text('execute_script'), findsOneWidget);
  });

  testWidgets('activity row expands to disclose its whole content',
      (tester) async {
    const content = {
      'skill': 'bwrap',
      'tool_name': 'execute_script',
      'args': '{"script":"print(42)"}',
    };
    events.value = const ClientToolExecuting(
      toolName: 'execute_skill',
      toolCallId: 'tc-1',
    );
    pushSnapshot(
      messageId: 'bwrap:call_1',
      activityType: 'skill_tool_call',
      content: content,
      timestamp: 100,
    );

    await tester.pumpWidget(wrap(build()));
    await tester.pump();
    await tester.tap(find.text('2 events'));
    await tester.pump();

    expect(find.textContaining('print(42)'), findsNothing);

    await tester.tap(find.text('execute_script'));
    await tester.pump();

    // Asserted whole rather than by substring: the contract is that the row
    // discloses every key the record carried, so replaying an old thread loses
    // nothing. A substring match would also pass if the row dropped a key.
    expect(
      find.text(const JsonEncoder.withIndent('  ').convert(content)),
      findsOneWidget,
    );
  });

  testWidgets('activity with empty content has no source chevron',
      (tester) async {
    pushSnapshot(
      messageId: 'bwrap:call_1',
      activityType: 'noop',
      content: const {},
      timestamp: 100,
    );

    await tester.pumpWidget(wrap(build()));
    await tester.pump();
    await tester.tap(find.text('1 event'));
    await tester.pump();

    // Only the header chevron should be visible, not a per-row one.
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets('completed step shows check_circle icon', (tester) async {
    events.value = const ServerToolCallStarted(
      toolName: 'search',
      toolCallId: 'tc-1',
    );
    events.value = const ServerToolCallCompleted(
      toolCallId: 'tc-1',
      result: 'ok',
    );

    await tester.pumpWidget(wrap(build()));
    await tester.pump();
    await tester.tap(find.text('1 event'));
    await tester.pump();

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('running step shimmers its label instead of showing a spinner',
      (tester) async {
    // Started-but-not-completed: the step stays active.
    events.value = const ServerToolCallStarted(
      toolName: 'search',
      toolCallId: 'tc-1',
    );

    await tester.pumpWidget(wrap(build()));
    await tester.pump();
    await tester.tap(find.text('1 event'));
    await tester.pump();

    // No anxiety-inducing spinner; the running rows shimmer instead.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(SoliplexShimmerText), findsWidgets);
  });

  testWidgets('standalone activity rendered when no active step',
      (tester) async {
    pushSnapshot(
      messageId: 'bwrap:call_1',
      activityType: 'skill_tool_call',
      content: {
        'tool_name': 'execute_script',
        'args': '{"script":"x=1"}',
      },
      timestamp: 100,
    );

    await tester.pumpWidget(wrap(build()));
    await tester.pump();
    await tester.tap(find.text('1 event'));
    await tester.pump();

    expect(find.text('execute_script'), findsOneWidget);
  });

  group('generic activity rendering', () {
    testWidgets('an unrecognised activityType renders, labelled by its type',
        (tester) async {
      // AG-UI defines an activity as an id-keyed store of opaque content, so
      // any activityType is renderable — the type names the row and the
      // content is its detail.
      pushSnapshot(
        messageId: 'plan:1',
        activityType: 'plan',
        content: {'steps': 3},
        timestamp: 100,
      );

      await tester.pumpWidget(wrap(build()));
      await tester.pump();
      await tester.tap(find.text('1 event'));
      await tester.pump();

      expect(find.text('plan'), findsOneWidget);

      await tester.tap(find.text('plan'));
      await tester.pump();

      expect(find.textContaining('"steps"'), findsOneWidget);
      // A body this short offers no disclosure, the same way a short tool
      // result does — the clamp is driven by measurement, not by the row kind.
      expect(find.text('Show more'), findsNothing);
    });

    testWidgets(
        'a row falls back to its activityType for every unusable '
        'tool_name', (tester) async {
      // One row per way the label read can fail. Each carries its own
      // activityType so a case that stopped falling back is identifiable
      // rather than just changing a count. The label is the whole subject
      // here; what a row discloses is covered by 'activity row expands to
      // disclose its whole content'.
      const cases = {
        'type_absent': <String, dynamic>{'other': 1},
        'type_wrong_type': <String, dynamic>{'tool_name': 42},
        'type_empty_string': <String, dynamic>{'tool_name': ''},
      };
      var i = 0;
      for (final entry in cases.entries) {
        pushSnapshot(
          messageId: 'rag:call_${i++}',
          activityType: entry.key,
          content: entry.value,
          timestamp: 100 + i,
        );
      }

      await tester.pumpWidget(wrap(build()));
      await tester.pump();
      await tester.tap(find.text('3 events'));
      await tester.pump();

      for (final activityType in cases.keys) {
        expect(find.text(activityType), findsOneWidget, reason: activityType);
      }
    });

    testWidgets('a long activity source is clamped until expanded',
        (tester) async {
      // A settled retrieval row discloses its whole content, and the `result`
      // inside is tens of KB of chunk text. Unclamped it buries every row
      // below it — the same reason a step row's result clamps. Encoding
      // escapes the newlines in that result, so this overflows by wrapping a
      // few enormous lines rather than by carrying many.
      final long = List.generate(40, (i) => 'chunk line $i').join('\n');
      pushSnapshot(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_result',
        content: {'tool_name': 'search', 'result': long},
        timestamp: 100,
      );

      await tester.pumpWidget(wrap(build()));
      await tester.pump();
      await tester.tap(find.text('1 event'));
      await tester.pump();
      await tester.tap(find.text('search'));
      await tester.pump();

      final body = find.textContaining('chunk line 0');
      expect(tester.widget<Text>(body).maxLines, 8);
      expect(find.text('Show more'), findsOneWidget);

      await tester.tap(find.text('Show more'));
      await tester.pump();

      expect(tester.widget<Text>(body).maxLines, isNull);
      expect(find.text('Show less'), findsOneWidget);
    });

    testWidgets('a stored call/result pair still renders one row',
        (tester) async {
      // Stored threads carry one sub-skill invocation as two snapshots
      // sharing a messageId, the result replacing the call in place. The row
      // must keep rendering across that boundary.
      pushSnapshot(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_call',
        content: {'tool_name': 'search', 'args': '{"query":"reentry"}'},
        timestamp: 100,
      );
      pushSnapshot(
        messageId: 'rag:call_1',
        activityType: 'skill_tool_result',
        content: {
          'tool_name': 'search',
          'result': 'found 3 documents',
          'status': 'done',
        },
        timestamp: 200,
      );

      await tester.pumpWidget(wrap(build()));
      await tester.pump();
      await tester.tap(find.text('1 event'));
      await tester.pump();

      expect(find.text('search'), findsOneWidget);

      await tester.tap(find.text('search'));
      await tester.pump();

      // The result phase carries no args, so the row discloses the content it
      // actually has — which is the result the reader wants to see.
      expect(find.textContaining('found 3 documents'), findsOneWidget);
    });
  });

  group('MessageExpansions persistence', () {
    testWidgets('header expansion persists across parent-key swap',
        (tester) async {
      events.value = const ThinkingStarted();

      Widget tree(Key parentKey) => wrap(
            KeyedSubtree(key: parentKey, child: build()),
          );

      await tester.pumpWidget(tree(const ValueKey('A')));
      await tester.pump();
      await tester.tap(find.text('1 event'));
      await tester.pump();
      expect(find.text('Thinking'), findsOneWidget);

      // Force State destruction by swapping the parent key; store is the
      // same across pumps, so the re-mounted widget seeds _expanded=true.
      await tester.pumpWidget(tree(const ValueKey('B')));
      await tester.pump();
      expect(find.text('Thinking'), findsOneWidget);
    });

    testWidgets('source expansion persists across parent-key swap',
        (tester) async {
      events.value = const ClientToolExecuting(
        toolName: 'execute_skill',
        toolCallId: 'tc-1',
      );
      pushSnapshot(
        messageId: 'bwrap:call_1',
        activityType: 'skill_tool_call',
        content: {
          'tool_name': 'execute_script',
          'args': '{"script":"print(42)"}',
        },
        timestamp: 100,
      );

      Widget tree(Key parentKey) => wrap(
            KeyedSubtree(key: parentKey, child: build()),
          );

      await tester.pumpWidget(tree(const ValueKey('A')));
      await tester.pump();
      await tester.tap(find.text('2 events'));
      await tester.pump();
      await tester.tap(find.text('execute_script'));
      await tester.pump();
      expect(find.textContaining('print(42)'), findsOneWidget);

      await tester.pumpWidget(tree(const ValueKey('B')));
      await tester.pump();
      expect(find.textContaining('print(42)'), findsOneWidget);
    });

    testWidgets('state is keyed by both roomId and messageId', (tester) async {
      events.value = const ThinkingStarted();

      final events2 = Signal<ExecutionEvent?>(null);
      final tracker2 = ExecutionTracker(
        executionEvents: events2,
        activities: Signal<List<ActivityRecord>>(const []),
        logger: testLogger(),
      );
      addTearDown(tracker2.dispose);
      events2.value = const ThinkingStarted();

      final events3 = Signal<ExecutionEvent?>(null);
      final tracker3 = ExecutionTracker(
        executionEvents: events3,
        activities: Signal<List<ActivityRecord>>(const []),
        logger: testLogger(),
      );
      addTearDown(tracker3.dispose);
      events3.value = const ThinkingStarted();

      // Three widgets: (r1, m1), (r1, other-msg), (other-room, m1).
      // Tapping the first must not affect the other two.
      await tester.pumpWidget(wrap(Column(
        children: [
          build(),
          build(messageId: 'other-msg', t: tracker2),
          build(roomId: 'other-room', t: tracker3),
        ],
      )));
      await tester.pump();
      expect(find.text('1 event'), findsNWidgets(3));

      await tester.tap(find.text('1 event').first);
      await tester.pump();

      // Only the first expands; isolation holds across messageId AND roomId.
      expect(find.text('Thinking'), findsOneWidget);
    });

    testWidgets('collapse persists across parent-key swap', (tester) async {
      events.value = const ThinkingStarted();

      Widget tree(Key parentKey) => wrap(
            KeyedSubtree(key: parentKey, child: build()),
          );

      await tester.pumpWidget(tree(const ValueKey('A')));
      await tester.pump();
      // Expand, then collapse.
      await tester.tap(find.text('1 event'));
      await tester.pump();
      await tester.tap(find.text('1 event'));
      await tester.pump();
      expect(find.text('Thinking'), findsNothing);

      // Remount — the collapsed state must survive. This pins the decision
      // to write every transition (not just expansion).
      await tester.pumpWidget(tree(const ValueKey('B')));
      await tester.pump();
      expect(find.text('Thinking'), findsNothing);
    });

    testWidgets('header toggle in loading phase uses local state only',
        (tester) async {
      events.value = const ThinkingStarted();

      await tester.pumpWidget(wrap(build(messageId: loadingMessageId)));
      await tester.pump();
      await tester.tap(find.text('1 event'));
      await tester.pump();
      expect(find.text('Thinking'), findsOneWidget);

      // Sentinel messageId must not leak into the store — it is reused
      // across runs and state written under it would leak to the next
      // response.
      expect(store.debugHasStateFor(_roomId, loadingMessageId), isFalse);
    });

    testWidgets('source toggle in loading phase uses local state only',
        (tester) async {
      events.value = const ClientToolExecuting(
        toolName: 'execute_skill',
        toolCallId: 'tc-1',
      );
      pushSnapshot(
        messageId: 'bwrap:call_1',
        activityType: 'skill_tool_call',
        content: {
          'tool_name': 'execute_script',
          'args': '{"script":"print(42)"}',
        },
        timestamp: 100,
      );

      await tester.pumpWidget(wrap(build(messageId: loadingMessageId)));
      await tester.pump();
      await tester.tap(find.text('2 events'));
      await tester.pump();
      await tester.tap(find.text('execute_script'));
      await tester.pump();
      expect(find.textContaining('print(42)'), findsOneWidget);

      // Collapse pins the "remove from local set" branch. A regression
      // that only adds and never removes would silently break the
      // loading-phase collapse path.
      await tester.tap(find.text('execute_script'));
      await tester.pump();
      expect(find.textContaining('print(42)'), findsNothing);

      // Safety invariant for source rows — no writes to the store.
      expect(store.debugHasStateFor(_roomId, loadingMessageId), isFalse);
    });
  });

  group('server tool call detail on the step row', () {
    // A retrieval is a first-class tool call: one step row per call, carrying
    // its own args and result. No nested row — the step *is* the call.
    Future<void> expand(WidgetTester tester, String stepLabel) async {
      await tester.tap(find.text('1 event'));
      await tester.pump();
      await tester.tap(find.text(stepLabel));
      await tester.pump();
    }

    testWidgets('expands to show arguments and result', (tester) async {
      events.value = const ServerToolCallStarted(
        toolName: 'analysis_execute_code',
        toolCallId: 'tc-1',
      );
      events.value = const ServerToolCallArgs(
        toolCallId: 'tc-1',
        delta: '{"code":"df.groupby(\'site\').mean()"}',
      );
      events.value = const ServerToolCallCompleted(
        toolCallId: 'tc-1',
        result: 'site   value\nA      12.4',
      );

      await tester.pumpWidget(wrap(build()));
      await tester.pump();
      await expand(tester, 'analysis_execute_code');

      // `code` is preferred over dumping the whole args object.
      expect(find.text("df.groupby('site').mean()"), findsOneWidget);
      // The result is the only place in the chat UI that a code execution's
      // stdout — or the message from a tool that raised — reaches the user.
      expect(find.text('site   value\nA      12.4'), findsOneWidget);
    });

    testWidgets('a call with no args and no result is not expandable',
        (tester) async {
      // The state of every tool call row between its start and its first delta,
      // of a call whose stream was truncated, and of a tool returning no output.
      // An empty grey block would be worse than no block.
      events.value = const ServerToolCallStarted(
        toolName: 'list_environments',
        toolCallId: 'tc-1',
      );
      events.value = const ServerToolCallCompleted(
        toolCallId: 'tc-1',
        result: '',
      );

      await tester.pumpWidget(wrap(build()));
      await tester.pump();
      await tester.tap(find.text('1 event'));
      await tester.pump();

      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.text('Arguments'), findsNothing);
      expect(find.text('Result'), findsNothing);
    });

    testWidgets('args of a tool that takes none yield no block',
        (tester) async {
      // A no-argument tool sends `{}`. Pretty-printing that produces a block
      // whose entire content is `{}` — an affordance hiding nothing.
      events.value = const ServerToolCallStarted(
        toolName: 'list_environments',
        toolCallId: 'tc-1',
      );
      events.value = const ServerToolCallArgs(toolCallId: 'tc-1', delta: '{}');

      await tester.pumpWidget(wrap(build()));
      await tester.pump();
      await tester.tap(find.text('1 event'));
      await tester.pump();

      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.text('{}'), findsNothing);
    });

    testWidgets('the clamp still applies when text is scaled up',
        (tester) async {
      // The clamp decision has to be measured at the scale the text renders at.
      // Measuring unscaled reports a scaled-up body as fitting, so it renders
      // in full with no control — the outcome the clamp exists to prevent.
      //
      // Deliberately one unbroken line: a body carrying explicit line breaks is
      // known to overflow without measuring, which would skip the path under
      // test. Its length has to straddle the clamp — short enough to fit
      // unscaled, long enough to overflow scaled — so both directions are
      // asserted and a length that drifts out of that band fails loudly.
      final wrapping = 'wrapped ' * 40;
      events.value = const ServerToolCallStarted(
        toolName: 'rag_search',
        toolCallId: 'tc-1',
      );
      events.value =
          ServerToolCallCompleted(toolCallId: 'tc-1', result: wrapping);

      await tester.pumpWidget(wrap(build()));
      await tester.pump();
      await expand(tester, 'rag_search');

      expect(
        tester.widget<Text>(find.text(wrapping)).maxLines,
        isNull,
        reason: 'Unscaled this body fits, so nothing should be clamped.',
      );
      expect(find.text('Show more'), findsNothing);

      // Scale the same open row in place. Set on the dispatcher, not as an
      // ancestor MediaQuery: MaterialApp installs its own from the view and
      // would override one above it.
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pump();

      expect(tester.widget<Text>(find.text(wrapping)).maxLines, 8);
      expect(find.text('Show more'), findsOneWidget);
    });

    testWidgets('a recognised argument key wins over the whole object',
        (tester) async {
      // `command` is the sandbox shell tool's argument; the preference list is
      // shared with the activity rows, so its contents are load-bearing twice.
      events.value = const ServerToolCallStarted(
        toolName: 'run',
        toolCallId: 'tc-1',
      );
      events.value = const ServerToolCallArgs(
        toolCallId: 'tc-1',
        delta: '{"command":"ls -la","environment_name":"default"}',
      );

      await tester.pumpWidget(wrap(build()));
      await tester.pump();
      await expand(tester, 'run');

      expect(find.text('ls -la'), findsOneWidget);
    });

    testWidgets('a step with no detail is not expandable', (tester) async {
      events.value = const ThinkingStarted();

      await tester.pumpWidget(wrap(build()));
      await tester.pump();
      await tester.tap(find.text('1 event'));
      await tester.pump();

      // The expanded header shows expand_more; a step with neither args nor a
      // result contributes no chevron of its own.
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('partial JSON args render raw rather than throwing',
        (tester) async {
      // While TOOL_CALL_ARGS is still streaming, the accumulated string is a
      // JSON prefix, so the formatter must not require it to parse.
      events.value = const ServerToolCallStarted(
        toolName: 'rag_search',
        toolCallId: 'tc-1',
      );
      events.value = const ServerToolCallArgs(
        toolCallId: 'tc-1',
        delta: '{"query":"Soli',
      );

      await tester.pumpWidget(wrap(build()));
      await tester.pump();
      await expand(tester, 'rag_search');

      expect(find.text('{"query":"Soli'), findsOneWidget);
    });

    testWidgets('a long result is clamped until expanded', (tester) async {
      // A rag_search result is 20-35 KB of chunk text. Showing all of it by
      // default buries the rest of the timeline.
      final long = List.generate(40, (i) => 'chunk line $i').join('\n');
      events.value = const ServerToolCallStarted(
        toolName: 'rag_search',
        toolCallId: 'tc-1',
      );
      events.value = ServerToolCallCompleted(
        toolCallId: 'tc-1',
        result: long,
      );

      await tester.pumpWidget(wrap(build()));
      await tester.pump();
      await expand(tester, 'rag_search');

      expect(tester.widget<Text>(find.text(long)).maxLines, 8);
      expect(find.text('Show more'), findsOneWidget);

      await tester.tap(find.text('Show more'));
      await tester.pump();

      expect(tester.widget<Text>(find.text(long)).maxLines, isNull);
      expect(find.text('Show less'), findsOneWidget);
      // The arrow points at what the tap does, so collapsing points up. A
      // down arrow beside "Show less" contradicts its own label.
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
    });

    testWidgets('a short result is not clamped and offers no disclosure',
        (tester) async {
      // Same principle as the step row's chevron: no affordance where nothing
      // is hidden.
      events.value = const ServerToolCallStarted(
        toolName: 'rag_cite',
        toolCallId: 'tc-1',
      );
      events.value = const ServerToolCallCompleted(
        toolCallId: 'tc-1',
        result: 'Registered 2 citation(s).',
      );

      await tester.pumpWidget(wrap(build()));
      await tester.pump();
      await expand(tester, 'rag_cite');

      expect(
        tester.widget<Text>(find.text('Registered 2 citation(s).')).maxLines,
        isNull,
      );
      expect(find.text('Show more'), findsNothing);
    });

    testWidgets("a call's args and result clamp independently", (tester) async {
      // One row discloses two bodies, so each needs its own clamp key. Sharing
      // one would make "Show more" under Arguments unclamp the Result too.
      final script = List.generate(40, (i) => 'script line $i').join('\n');
      final result = List.generate(40, (i) => 'result line $i').join('\n');
      events.value = const ServerToolCallStarted(
        toolName: 'run_python',
        toolCallId: 'tc-1',
      );
      events.value = ServerToolCallArgs(
        toolCallId: 'tc-1',
        delta: jsonEncode({'script': script}),
      );
      events.value = ServerToolCallCompleted(
        toolCallId: 'tc-1',
        result: result,
      );

      await tester.pumpWidget(wrap(build()));
      await tester.pump();
      await expand(tester, 'run_python');

      expect(tester.widget<Text>(find.text(script)).maxLines, 8);
      expect(tester.widget<Text>(find.text(result)).maxLines, 8);

      // The Arguments block renders first, so its control comes first.
      await tester.tap(find.text('Show more').first);
      await tester.pump();

      expect(tester.widget<Text>(find.text(script)).maxLines, isNull);
      expect(
        tester.widget<Text>(find.text(result)).maxLines,
        8,
        reason: 'Sharing one clamp key would unclamp the result as well.',
      );
    });

    testWidgets("one call's result expansion does not affect another's",
        (tester) async {
      // The clamp is keyed per call, so expanding one long result must not
      // unclamp every other row in the run.
      final long = List.generate(40, (i) => 'line $i').join('\n');
      for (final id in ['tc-1', 'tc-2']) {
        events.value = ServerToolCallStarted(
          toolName: 'rag_search_$id',
          toolCallId: id,
        );
        events.value = ServerToolCallCompleted(toolCallId: id, result: long);
      }

      await tester.pumpWidget(wrap(build()));
      await tester.pump();
      await tester.tap(find.text('2 events'));
      await tester.pump();
      await tester.tap(find.text('rag_search_tc-1'));
      await tester.tap(find.text('rag_search_tc-2'));
      await tester.pump();

      await tester.tap(find.text('Show more').first);
      await tester.pump();

      expect(find.text('Show less'), findsOneWidget);
      expect(find.text('Show more'), findsOneWidget);
    });

    testWidgets('args with no recognised key fall back to pretty JSON',
        (tester) async {
      // Args carrying no recognised key: the whole object is the only thing
      // worth showing.
      events.value = const ServerToolCallStarted(
        toolName: 'execute_skill',
        toolCallId: 'tc-1',
      );
      events.value = const ServerToolCallArgs(
        toolCallId: 'tc-1',
        delta: '{"request":"Search the docs","skill_name":"rag"}',
      );

      await tester.pumpWidget(wrap(build()));
      await tester.pump();
      await expand(tester, 'execute_skill');

      expect(
        find.text('{\n  "request": "Search the docs",\n'
            '  "skill_name": "rag"\n}'),
        findsOneWidget,
      );
    });
  });

  group('step duration', () {
    testWidgets('renders the offset derived from the stored event times',
        (tester) async {
      final historical = ExecutionTracker.historical(
        origin: 1000,
        events: const [
          (event: ThinkingStarted(), timestamp: 1000),
          (
            event:
                ServerToolCallStarted(toolName: 'search', toolCallId: 'tc-1'),
            timestamp: 3100,
          ),
          (event: RunCompleted(), timestamp: 5000),
        ],
        activities: const [],
        logger: testLogger(),
      );
      addTearDown(historical.dispose);

      await tester.pumpWidget(wrap(build(t: historical)));
      await tester.pump();
      await tester.tap(find.text('2 events'));
      await tester.pump();

      expect(find.text('2.1s'), findsOneWidget);
      expect(find.text('4.0s'), findsOneWidget);
    });

    testWidgets('shows no duration for a step with no known time',
        (tester) async {
      // Stored events that carry no emission time give nothing to offset
      // from; the row must say nothing rather than claim 0.0s.
      final historical = ExecutionTracker.historical(
        origin: null,
        events: const [
          (event: ThinkingStarted(), timestamp: null),
          (event: RunCompleted(), timestamp: null),
        ],
        activities: const [],
        logger: testLogger(),
      );
      addTearDown(historical.dispose);

      await tester.pumpWidget(wrap(build(t: historical)));
      await tester.pump();
      await tester.tap(find.text('1 event'));
      await tester.pump();

      expect(find.text('Thinking'), findsOneWidget);
      expect(find.textContaining(RegExp(r'\d\.\ds')), findsNothing);
    });
  });
}
